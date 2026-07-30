# LocalLLM Cactus workspace

This repository contains two focused pieces:

- conversion/ converts an existing Hugging Face checkpoint to Cactus weights and optionally uploads the result.
- natural_farming_chat/ is the Flutter application and local cactus plugin used to build Android, iOS, and macOS targets.

## Convert a model

The converter expects a completed Hugging Face model directory containing one or more .safetensors files. Fine-tuning and dataset preparation happen outside this repository.

    bash conversion/convert_to_cactus.sh --merged-model /path/to/model --output models/cactus-model --bits 4 --cache-context-length 2048

The script clones or reuses the Cactus SDK and uses its official CLI to create the CQ weights and runtime components required by the Flutter package. The SDK checkout and model output are ignored by git.

For multimodal checkpoints that do not need their vision tower on-device, run conversion/strip_vision_encoder.py before conversion. conversion/upload_to_hf.sh can publish a converted directory as a zip archive.

## Build the Flutter targets

    cd natural_farming_chat
    flutter pub get
    flutter build apk --release

On macOS, the same project can build Apple targets with flutter build ios --release or flutter build macos --release.

The vendored plugin is at natural_farming_chat/packages/cactus; its upstream-style example is available under natural_farming_chat/packages/cactus/example.
