# Natural Farming Chat for the Pixel 7 (Qwen3)

An Android app that runs a fine-tuned Qwen3-0.6B natural-farming model on the phone with the [Cactus](https://github.com/cactus-compute/cactus) engine (Pixel 7 is the reference device). This repository holds exactly that and nothing else: the Flutter app with its Cactus plugin, and the scripts that convert a model to Cactus weights.

The newer Qwen3.5 recipe app is a separate repository: [`pixel7-cactus-qwen3.5`](https://github.com/CopyleftCultivars/pixel7-cactus-qwen3.5). Training lives in [`qwen3-finetune`](https://github.com/CopyleftCultivars/qwen3-finetune).

## The model

The app downloads its model on first launch (`lib/services/model_service.dart`): the calibrated Cactus int4 build of the **distill-v2-rationale** model (Qwen3-0.6B), from [`CopyleftCultivars/localNFchatbot-cactus`](https://huggingface.co/CopyleftCultivars/localNFchatbot-cactus) (`qwen3-distill-v2-calibrated-cact-int4-ios.zip`).

On Hugging Face, same organization:

* merged weights: [`qwen3-distill-v2-rationale-0.6b`](https://huggingface.co/CopyleftCultivars/qwen3-distill-v2-rationale-0.6b) (a 1.7B variant is [`-1.7b`](https://huggingface.co/CopyleftCultivars/qwen3-distill-v2-rationale-1.7b))
* the earlier v5clean champion: [`qwen3-v5clean`](https://huggingface.co/CopyleftCultivars/qwen3-v5clean)
* more Cactus bundles in `localNFchatbot-cactus`, including Android arm64 builds (`qwen3-distill-v2-calibrated-cact-int4-arm64.zip`, `qwen3-v5clean-cact-int4-arm64.zip`)

## Layout

| Path | What it is |
|---|---|
| `natural_farming_chat/` | the Flutter app (`lib/`, `assets/`, `test/`, `android/`) |
| `natural_farming_chat/packages/cactus/` | the local Cactus Dart plugin (Android) |
| `natural_farming_chat/integration_test/` | on-device benchmark tests (ladder and free-form); the benchmark logic is meant to move to the benchmark repository later |
| `conversion/` | `convert_to_cactus.sh` (Hugging Face checkpoint to Cactus CQ weights) and `upload_to_hf.sh` |
| `Dockerfile`, `flake.nix` | an Android build environment (Docker image with adb deploy, or a Nix dev shell) |

## Build

```sh
cd natural_farming_chat
flutter pub get
flutter test
flutter build apk --release
```

`libcactus.so` is tracked through Git LFS (`.gitattributes`); the working copy needs the real library in `natural_farming_chat/packages/cactus/android/src/main/jniLibs/arm64-v8a/`. The Qwen3.5 repository documents a checksum-pinned fetch of a Cactus build; that script is not part of this repository.

## Convert a model

```sh
bash conversion/convert_to_cactus.sh --merged-model /path/to/hf-model --output models/cactus-model --bits 4 --cache-context-length 2048
```

See `conversion/README.md`. Fine-tuning and dataset preparation happen in `qwen3-finetune`.

## Licenses

Cactus (the engine and its plugin) is under Cactus Compute's own license: free for individuals using it non-commercially, educational institutions, 501(c)(3) non-profits and organizations with under $2 million in funding and revenue; everyone else needs a commercial license, and the license text must accompany copies. Qwen3 is Apache-2.0.
