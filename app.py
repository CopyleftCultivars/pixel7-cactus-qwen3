import os
import re
import yaml
from io import BytesIO
import streamlit as st
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM, pipeline, BitsAndBytesConfig
from langchain_community.embeddings import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma
from PIL import Image
from gtts import gTTS
from sympy import sympify, simplify
from dotenv import load_dotenv

load_dotenv()

# Set environment variable to reduce memory fragmentation
os.environ['PYTORCH_CUDA_ALLOC_CONF'] = 'expandable_segments:True'

# --- Configuration & Setup ---
st.set_page_config(page_title="Natural Farming Chat", layout="wide")

@st.cache_resource
def load_config():
    """Load configuration from YAML file."""
    with open('config.yaml', 'r') as f:
        return yaml.safe_load(f)

@st.cache_resource
def init_embeddings():
    """Initialize embedding model."""
    config = load_config()
    device = config['embeddings']['device'] if torch.cuda.is_available() else 'cpu'
    
    embeddings = HuggingFaceEmbeddings(
        model_name=config['embeddings']['model_name'],
        model_kwargs={'device': device},
        encode_kwargs={'normalize_embeddings': True}
    )
    return embeddings

@st.cache_resource
def init_vector_store():
    """Initialize local vector store."""
    config = load_config()
    embeddings = init_embeddings()
    
    persist_dir = config['vector_store']['persist_directory']
    
    if not os.path.exists(persist_dir):
        st.error(f"Vector store not found at {persist_dir}. Please run local_indexer.py first!")
        st.stop()
    
    vectorstore = Chroma(
        collection_name=config['vector_store']['collection_name'],
        embedding_function=embeddings,
        persist_directory=persist_dir
    )
    
    return vectorstore

@st.cache_resource
def init_llm():
    """Initialize local LLM."""
    config = load_config()

    device = config['llm']['device'] if torch.cuda.is_available() else 'cpu'

    # Clear GPU cache before loading
    if torch.cuda.is_available():
        torch.cuda.empty_cache()

    st.sidebar.info(f"Loading LLM: {config['llm']['model_name']}")
    st.sidebar.info(f"Device: {device}")

    # Load tokenizer
    tokenizer = AutoTokenizer.from_pretrained(config['llm']['model_name'])
    
    # Load model with optional quantization
    model_kwargs = {
        'low_cpu_mem_usage': True,  # Better memory management during loading
        'torch_dtype': torch.float16,  # Use fp16 as base dtype
    }

    # Configure quantization if enabled
    if config['llm'].get('load_in_4bit', False) and device == 'cuda':
        # 4-bit quantization (QLoRA) for maximum memory savings
        quantization_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_use_double_quant=True,  # Nested quantization for extra savings
            bnb_4bit_quant_type="nf4"  # Normal Float 4-bit
        )
        model_kwargs['quantization_config'] = quantization_config
        model_kwargs['device_map'] = 'auto'
        # Remove torch_dtype when using quantization
        del model_kwargs['torch_dtype']
    elif config['llm'].get('load_in_8bit', False) and device == 'cuda':
        # 8-bit quantization (fallback)
        quantization_config = BitsAndBytesConfig(load_in_8bit=True)
        model_kwargs['quantization_config'] = quantization_config
        model_kwargs['device_map'] = 'auto'
        # Remove torch_dtype when using quantization
        del model_kwargs['torch_dtype']
    elif device == 'cuda':
        model_kwargs['device_map'] = 'auto'
    else:
        model_kwargs['torch_dtype'] = torch.float32

    model = AutoModelForCausalLM.from_pretrained(
        config['llm']['model_name'],
        **model_kwargs
    )
    
    # Create pipeline
    pipe = pipeline(
        "text-generation",
        model=model,
        tokenizer=tokenizer,
        max_length=config['llm']['max_length'],
        temperature=config['llm']['temperature'],
        do_sample=True,
        top_p=0.95,
        repetition_penalty=1.15
    )
    
    return pipe

# --- Tool Logic ---

def calculator_tool(expression: str) -> str:
    """Safe calculator using sympy."""
    try:
        if len(expression) > 200:
            return "Error: Expression too long"
        
        result = sympify(expression.strip())
        if result.is_number:
            return str(float(result))
        else:
            return str(simplify(result))
    except Exception as e:
        return f"Error in calculation: {str(e)}"

def extract_tool_calls(text: str):
    """Extract tool calls from AI response."""
    tool_calls = []
    calc_pattern = r'<calculate>(.*?)</calculate>'
    matches = re.findall(calc_pattern, text, re.DOTALL)
    for match in matches:
        tool_calls.append(("calculator", match.strip()))
    return tool_calls

def replace_tool_calls_with_results(text: str, tool_results: dict):
    """Replace tool call markers with actual results."""
    def replace_calc(match):
        expression = match.group(1).strip()
        if expression in tool_results:
            return f"**Calculation Result:** {tool_results[expression]}"
        return match.group(0)
    
    return re.sub(r'<calculate>(.*?)</calculate>', replace_calc, text, flags=re.DOTALL)

# --- Core Generation Logic ---

def retrieve_context(question, vectorstore, top_k=3):
    """Retrieve relevant context from vector store."""
    config = load_config()
    
    results = vectorstore.similarity_search_with_score(
        question,
        k=top_k
    )
    
    threshold = config['retrieval']['similarity_threshold']
    
    # Filter by similarity threshold and format
    contexts = []
    for doc, score in results:
        # ChromaDB returns distance, lower is better
        # Convert to similarity (1 - distance for L2, or use cosine)
        similarity = 1 - score if score < 1 else 0
        
        if similarity > threshold:
            contexts.append(doc.page_content)
    
    return "\n\n".join(contexts)

def generate_response_logic(question, vectorstore, llm_pipeline, agentic_mode=False, max_iterations=3):
    """Core logic for generating responses."""
    config = load_config()
    
    # 1. Retrieve relevant context
    retrieved_context = retrieve_context(
        question,
        vectorstore,
        top_k=config['retrieval']['top_k']
    )
    
    # 2. Build conversation context
    recent_messages = st.session_state.messages[-5:]
    conversation_context = "\n".join([
        f"{m['role'].upper()}: {m['content']}" 
        for m in recent_messages
    ])
    
    # 3. Build system prompt
    system_prompt = config['master_prompt']
    
    if agentic_mode:
        system_prompt += """\n\nAGENTIC MODE:
You have access to a calculator. Use <calculate>expression</calculate> for math.
I will parse this tag, run the math, and return the result.
Make multiple iterations if necessary."""
    
    # 4. Build full prompt
    full_prompt = f"""{system_prompt}

Previous conversation:
{conversation_context}

Relevant knowledge:
{retrieved_context}

Current question: {question}

Please provide a helpful, accurate answer based on the context above."""
    
    # 5. Iterative generation with tool use
    current_iteration = 0
    accumulated_prompt = full_prompt
    tool_results_history = {}
    final_response_text = ""
    
    while current_iteration < max_iterations:
        try:
            # Generate response
            outputs = llm_pipeline(
                accumulated_prompt,
                max_new_tokens=256,  # Reduced to save GPU memory
                return_full_text=False
            )
            
            response_text = outputs[0]['generated_text'].strip()
            final_response_text = response_text
            
            # Check for tool calls in agentic mode
            if agentic_mode:
                tool_calls = extract_tool_calls(response_text)
                
                if tool_calls:
                    iteration_results = {}
                    for tool_name, tool_input in tool_calls:
                        if tool_name == "calculator":
                            res = calculator_tool(tool_input)
                            iteration_results[tool_input] = res
                            tool_results_history[tool_input] = res
                    
                    if iteration_results:
                        # Append results and continue
                        tool_output_str = "\n".join([
                            f"Calculation: {k} = {v}" 
                            for k, v in iteration_results.items()
                        ])
                        accumulated_prompt += f"\n\nAI partial response: {response_text}\nSystem Tool Output:\n{tool_output_str}\nPlease continue."
                        current_iteration += 1
                        continue
            
            # No tools used or max iterations reached
            break
            
        except Exception as e:
            return f"Error generating response: {str(e)}"
    
    # Replace tool calls with results in final response
    if tool_results_history:
        final_response_text = replace_tool_calls_with_results(
            final_response_text,
            tool_results_history
        )
    
    return final_response_text

# --- Main UI ---

def launch_bot():
    config = load_config()
    
    # Initialize resources (cached)
    vectorstore = init_vector_store()
    llm_pipeline = init_llm()
    
    # Sidebar
    with st.sidebar:
        try:
            image = Image.open('Vectara-logo.png')
            st.image(image, width=250)
        except:
            st.write("🌱 **Natural Farming AI**")
        
        st.markdown("---")
        
        # Model info
        st.markdown("### **System Info**")
        device = "GPU" if torch.cuda.is_available() else "CPU"
        st.info(f"🖥️ Running on: {device}")
        
        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name(0)
            st.info(f"GPU: {gpu_name}")
        
        st.markdown("---")
        st.markdown("### **Agentic Mode**")
        agentic_mode = st.checkbox(
            "Enable Agentic Mode",
            value=st.session_state.get('agentic_mode', False),
            help="Allows calculator usage and multi-step reasoning."
        )
        st.session_state.agentic_mode = agentic_mode
        
        st.markdown("---")
        st.markdown("### **Settings**")
        
        # Clear history button
        if st.button("Clear Chat History"):
            st.session_state.messages = [
                {"role": "assistant", "content": "How may I help you?"}
            ]
            st.rerun()
        
        st.markdown("---")
        st.markdown("*Democratizing access to farming knowledge*")
        st.markdown("**100% Local • Privacy First**")
    
    # Main chat interface
    st.title("🌾 Natural Farming Chat")
    st.caption("AI Agriculture Assistant - Fully Local & Open Source")
    
    if st.session_state.agentic_mode:
        st.info("🤖 **Agentic Mode Active** - Calculator tools enabled")
    
    # Initialize chat history
    if "messages" not in st.session_state:
        st.session_state.messages = [
            {"role": "assistant", "content": "How may I help you today?"}
        ]
    
    # Display chat messages
    for message in st.session_state.messages:
        with st.chat_message(message["role"]):
            st.write(message["content"])
    
    # Chat input
    if prompt := st.chat_input("Ask about natural farming..."):
        # Add user message
        st.session_state.messages.append({"role": "user", "content": prompt})
        with st.chat_message("user"):
            st.write(prompt)
        
        # Generate assistant response
        with st.chat_message("assistant"):
            with st.spinner("Thinking..."):
                response_text = generate_response_logic(
                    prompt,
                    vectorstore,
                    llm_pipeline,
                    agentic_mode=st.session_state.agentic_mode
                )
                
                st.write(response_text)
                st.session_state.messages.append(
                    {"role": "assistant", "content": response_text}
                )
                
                # Audio generation (optional)
                with st.expander("🔊 Audio Response"):
                    try:
                        sound_file = BytesIO()
                        tts = gTTS(response_text, lang='en')
                        tts.write_to_fp(sound_file)
                        st.audio(sound_file)
                    except Exception as e:
                        st.warning(f"Audio generation failed: {str(e)}")

if __name__ == "__main__":
    launch_bot()