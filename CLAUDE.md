# Claude Project Notes

## Flutter Development

### Running Flutter Commands
**IMPORTANT**: Flutter is installed via snap and cannot be run directly from the Bash tool due to snap confinement. Instead of running flutter commands directly, prompt the user to run the command and paste the output back to the chat session.

Example prompt:
> Please run this command and paste the output:
> ```
> cd natural_farming_chat && flutter analyze
> ```

### Common Commands to Prompt
- `flutter analyze` - Check for code issues
- `flutter pub get` - Get dependencies
- `flutter build apk` - Build release APK
- `flutter run` - Run on connected device

### Project Structure
- Main Flutter app: `natural_farming_chat/`
- Services: `natural_farming_chat/lib/services/`
  - `model_service.dart` - CactusLM model operations
  - `rag_service.dart` - CactusRAG vector storage and retrieval
