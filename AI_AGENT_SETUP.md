# AI Agent Setup Guide

## How to Make This Database Accessible to AI Agents

This document explains multiple methods for making the bioaccumulator database accessible to AI agents for fertilizer formulation.

---

## Method 1: Direct API Integration (Simplest)

### Setup

1. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

2. **Load your data**:
   ```python
   from bioaccumulator_api import BioaccumulatorDB

   db = BioaccumulatorDB()
   db.load_data('Nutrient_Bioaccumulator_combined_data.xlsx')

   # Export to JSON for AI access
   db.export_to_json('bioaccumulator_data.json')
   ```

3. **Provide to AI agent**:
   - Upload JSON file to AI's context
   - Reference in system prompt
   - AI can query directly from JSON

### Example AI Query

```python
# AI can read and parse the JSON
import json

with open('bioaccumulator_data.json') as f:
    data = json.load(f)

# Find high nitrogen plants
nitrogen_plants = [
    plant for plant in data['plants']
    if plant['nutrients'].get('nitrogen', {}).get('average', 0) >= 2.5
]
```

---

## Method 2: REST API Service

Create a simple web service for remote access.

### Simple Flask API Example

```python
# fertilizer_api_server.py
from flask import Flask, jsonify, request
from bioaccumulator_api import BioaccumulatorDB

app = Flask(__name__)
db = BioaccumulatorDB('Nutrient_Bioaccumulator_combined_data.xlsx')

@app.route('/api/nutrients', methods=['GET'])
def get_nutrients():
    """Get list of available nutrients"""
    return jsonify(db.get_available_nutrients())

@app.route('/api/plants/search', methods=['GET'])
def search_plants():
    """Search plants by nutrient"""
    nutrient = request.args.get('nutrient')
    min_value = float(request.args.get('min_value', 0))

    results = db.find_by_nutrient(nutrient, min_value=min_value)
    return jsonify(results.to_dict('records'))

@app.route('/api/plant/<name>', methods=['GET'])
def get_plant(name):
    """Get specific plant info"""
    return jsonify(db.get_plant_info(name))

@app.route('/api/formulation', methods=['POST'])
def create_formulation():
    """Create fertilizer formulation"""
    data = request.json
    target_npk = tuple(data['target_npk'])
    available = data.get('available_plants')

    result = db.create_formulation(target_npk, available)
    return jsonify(result)

if __name__ == '__main__':
    app.run(debug=True, port=5000)
```

### Usage

```bash
# Start server
python fertilizer_api_server.py

# Query from AI agent
curl http://localhost:5000/api/plants/search?nutrient=Nitrogen&min_value=2.5

curl -X POST http://localhost:5000/api/formulation \
  -H "Content-Type: application/json" \
  -d '{"target_npk": [5, 5, 5], "available_plants": ["Comfrey", "Alfalfa", "Kelp"]}'
```

---

## Method 3: MCP (Model Context Protocol) Server

For integration with Claude Desktop and other MCP-compatible AI systems.

### MCP Server Implementation

```python
# mcp_bioaccumulator_server.py
from mcp.server import Server, NotificationOptions
from mcp.server.models import InitializationOptions
import mcp.server.stdio
import mcp.types as types
from bioaccumulator_api import BioaccumulatorDB

# Initialize database
db = BioaccumulatorDB('Nutrient_Bioaccumulator_combined_data.xlsx')

# Create MCP server
server = Server("bioaccumulator-fertilizer")

@server.list_tools()
async def handle_list_tools() -> list[types.Tool]:
    """List available tools"""
    return [
        types.Tool(
            name="find_nutrient_sources",
            description="Find plants that accumulate a specific nutrient",
            inputSchema={
                "type": "object",
                "properties": {
                    "nutrient": {
                        "type": "string",
                        "description": "Nutrient name (e.g., Nitrogen, Phosphorus, Potassium)"
                    },
                    "min_value": {
                        "type": "number",
                        "description": "Minimum concentration percentage"
                    }
                },
                "required": ["nutrient"]
            }
        ),
        types.Tool(
            name="get_plant_info",
            description="Get detailed nutrient information for a specific plant",
            inputSchema={
                "type": "object",
                "properties": {
                    "plant_name": {
                        "type": "string",
                        "description": "Name of the plant"
                    }
                },
                "required": ["plant_name"]
            }
        ),
        types.Tool(
            name="create_formulation",
            description="Create a fertilizer formulation to match target NPK ratio",
            inputSchema={
                "type": "object",
                "properties": {
                    "target_n": {"type": "number"},
                    "target_p": {"type": "number"},
                    "target_k": {"type": "number"},
                    "available_plants": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "List of available plants (optional)"
                    }
                },
                "required": ["target_n", "target_p", "target_k"]
            }
        )
    ]

@server.call_tool()
async def handle_call_tool(
    name: str, arguments: dict | None
) -> list[types.TextContent | types.ImageContent | types.EmbeddedResource]:
    """Handle tool calls"""

    if name == "find_nutrient_sources":
        nutrient = arguments.get("nutrient")
        min_value = arguments.get("min_value", 0)

        results = db.find_by_nutrient(nutrient, min_value=min_value)
        return [types.TextContent(
            type="text",
            text=results.to_json(orient="records", indent=2)
        )]

    elif name == "get_plant_info":
        plant_name = arguments.get("plant_name")
        info = db.get_plant_info(plant_name)

        if info:
            return [types.TextContent(type="text", text=str(info))]
        else:
            return [types.TextContent(type="text", text=f"Plant '{plant_name}' not found")]

    elif name == "create_formulation":
        target_npk = (
            arguments.get("target_n"),
            arguments.get("target_p"),
            arguments.get("target_k")
        )
        available = arguments.get("available_plants")

        formulation = db.create_formulation(target_npk, available)
        return [types.TextContent(
            type="text",
            text=str(formulation)
        )]

    else:
        raise ValueError(f"Unknown tool: {name}")

async def main():
    async with mcp.server.stdio.stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name="bioaccumulator",
                server_version="1.0.0",
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                )
            )
        )

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

### Claude Desktop Configuration

Add to `claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "bioaccumulator": {
      "command": "python",
      "args": ["/path/to/mcp_bioaccumulator_server.py"]
    }
  }
}
```

---

## Method 4: RAG (Retrieval Augmented Generation)

For AI systems with vector database support.

### Setup Vector Database

```python
from langchain.document_loaders import JSONLoader
from langchain.embeddings import OpenAIEmbeddings
from langchain.vectorstores import Chroma
from bioaccumulator_api import BioaccumulatorDB

# Export data
db = BioaccumulatorDB('data.xlsx')
db.export_to_json('bioaccumulator_data.json')

# Load into vector store
loader = JSONLoader(
    file_path='bioaccumulator_data.json',
    jq_schema='.plants[]',
    text_content=False
)

documents = loader.load()
embeddings = OpenAIEmbeddings()
vectorstore = Chroma.from_documents(documents, embeddings)

# Now AI can query semantically
results = vectorstore.similarity_search(
    "plants high in nitrogen for leafy greens",
    k=5
)
```

---

## Method 5: Static Documentation for Context

For maximum simplicity, provide comprehensive markdown documentation.

### Files to Include in AI Context

1. **README.md** - Overview and usage
2. **FORMULATION_GUIDE.md** - Detailed fertilizer formulation instructions
3. **bioaccumulator_schema.json** - Data structure
4. **examples/sample_data.json** - Example plant data
5. **examples/example_queries.md** - Query patterns

### AI System Prompt

```
You have access to a bioaccumulator plant database for organic fertilizer formulation.

Context Documents:
- README.md: Database overview
- FORMULATION_GUIDE.md: NPK calculation methods
- sample_data.json: Example plant nutrient data

When users ask about fertilizers:
1. Reference the appropriate plants from the database
2. Calculate NPK ratios using the formulation guide
3. Provide specific mixing instructions

Example plants in database:
- Comfrey: N=2.15%, P=0.5%, K=4.4%
- Alfalfa: N=2.5%, P=0.55%, K=2.0%
- Nettle: N=3.25%, P=0.4%, K=2.0%
- Kelp: N=1.25%, P=0.2%, K=3.0%
```

---

## Recommended Approach by Use Case

### For Chatbots/Assistants
**Best**: Method 1 (Direct JSON) or Method 3 (MCP)
- Simple integration
- Low latency
- Easy updates

### For Web Applications
**Best**: Method 2 (REST API)
- Standard HTTP interface
- Easy to scale
- Language agnostic

### For Advanced AI Systems
**Best**: Method 4 (RAG)
- Semantic search
- Handles large databases
- Natural language queries

### For Maximum Compatibility
**Best**: Method 5 (Static Docs)
- Works with any AI
- No infrastructure needed
- Copy-paste friendly

---

## Testing Your Setup

### Basic Test Script

```python
from bioaccumulator_api import BioaccumulatorDB
import json

# Load database
db = BioaccumulatorDB('Nutrient_Bioaccumulator_combined_data.xlsx')

# Test 1: Find nitrogen sources
print("Test 1: High nitrogen plants")
nitrogen = db.find_by_nutrient('Nitrogen', min_value=2.5)
print(f"Found {len(nitrogen)} plants")
print(nitrogen[['Plant Name', 'Min. Nitrogen', 'Max. Nitrogen']].head())

# Test 2: Get plant info
print("\nTest 2: Comfrey information")
comfrey = db.get_plant_info('Comfrey')
print(json.dumps(comfrey, indent=2))

# Test 3: Create formulation
print("\nTest 3: Balanced fertilizer formulation")
formulation = db.create_formulation(
    target_npk=(5, 5, 5),
    available_plants=['Comfrey', 'Alfalfa', 'Kelp']
)
print(json.dumps(formulation, indent=2))

# Test 4: Export to JSON
print("\nTest 4: Export to JSON")
db.export_to_json('test_export.json')
print("Export complete")

print("\n✓ All tests passed!")
```

---

## Security Considerations

### If Exposing as Web Service:

1. **Rate Limiting**: Prevent abuse
   ```python
   from flask_limiter import Limiter
   limiter = Limiter(app, default_limits=["100 per hour"])
   ```

2. **Authentication**: Add API keys
   ```python
   @app.before_request
   def verify_api_key():
       if request.headers.get('X-API-Key') != SECRET_KEY:
           abort(401)
   ```

3. **Input Validation**: Sanitize queries
   ```python
   from flask import escape
   nutrient = escape(request.args.get('nutrient'))
   ```

4. **CORS Configuration**: Control access
   ```python
   from flask_cors import CORS
   CORS(app, origins=['https://yourdomain.com'])
   ```

---

## Performance Optimization

### For Large Databases:

1. **Caching**: Store frequent queries
   ```python
   from functools import lru_cache

   @lru_cache(maxsize=128)
   def cached_find_nutrient(nutrient, min_value):
       return db.find_by_nutrient(nutrient, min_value)
   ```

2. **Indexing**: Speed up searches
   ```python
   # Create indexed columns
   df.set_index('Plant Name', inplace=True)
   ```

3. **Async Processing**: Handle concurrent requests
   ```python
   from fastapi import FastAPI
   app = FastAPI()

   @app.get("/plants/{nutrient}")
   async def get_plants(nutrient: str):
       return await async_find_nutrient(nutrient)
   ```

---

## Maintenance

### Updating the Database

```python
# 1. Update source Excel file
# 2. Re-run processor
python BioAccumulatorXlsPageMerger.py

# 3. Reload in API
db.load_data('Nutrient_Bioaccumulator_combined_data.xlsx')

# 4. Re-export for AI agents
db.export_to_json('bioaccumulator_data.json')

# 5. Restart services if needed
```

### Version Control

```bash
# Tag releases
git tag -a v1.0.0 -m "Initial bioaccumulator database"
git push --tags

# Track data changes
git add Nutrient_Bioaccumulator_combined_data.xlsx
git commit -m "Update: Added 15 new plant species"
```

---

## Getting Started Checklist

- [ ] Install Python dependencies (`pip install -r requirements.txt`)
- [ ] Place your data file in the repository
- [ ] Test the API with sample queries
- [ ] Choose integration method (JSON/API/MCP)
- [ ] Configure AI agent with system prompt
- [ ] Test end-to-end with sample questions
- [ ] Document any custom plants added
- [ ] Set up automatic updates if data changes frequently

---

## Support and Resources

- **API Documentation**: See `bioaccumulator_api.py` docstrings
- **Example Queries**: See `examples/example_queries.md`
- **Formulation Math**: See `FORMULATION_GUIDE.md`
- **Schema Reference**: See `bioaccumulator_schema.json`

For questions or issues, open a GitHub issue in this repository.
