import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:cactus_rag_preprocessor/services/chunker.dart';
import 'package:cactus_rag_preprocessor/services/embedder.dart';
import 'package:cactus_rag_preprocessor/services/database.dart';

/// Maximum file size to load entirely into memory (10MB)
const int maxFileSizeBytes = 10 * 1024 * 1024;

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('input', abbr: 'i', help: 'Input file or directory (required)')
    ..addOption('output', abbr: 'o', help: 'Output ObjectBox directory (required)')
    ..addOption('api-url', defaultsTo: 'http://localhost:11434', help: 'Embedding API URL')
    ..addOption('api-model', defaultsTo: 'mxbai-embed-large', help: 'Embedding model name')
    ..addOption('chunk-size', defaultsTo: '512', help: 'Characters per chunk')
    ..addOption('chunk-overlap', defaultsTo: '64', help: 'Overlap between chunks')
    ..addOption('extensions', abbr: 'e', defaultsTo: '.txt,.md', help: 'File extensions to process')
    ..addFlag('verbose', abbr: 'v', negatable: false, help: 'Verbose output')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help');

  ArgResults args;
  try {
    args = parser.parse(arguments);
  } catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln('\nUsage: dart run bin/preprocess.dart [options]');
    stderr.writeln(parser.usage);
    exit(1);
  }

  if (args['help'] as bool) {
    print('Cactus RAG Preprocessor');
    print('');
    print('Preprocesses documents into an ObjectBox database with embeddings.');
    print('The generated database can be bundled with a Flutter app for mobile RAG.');
    print('');
    print('Usage: dart run bin/preprocess.dart [options]');
    print('');
    print('Requirements:');
    print('  - Ollama running with mxbai-embed-large model (1024 dimensions)');
    print('  - ObjectBox version must match Flutter app (currently 5.0.4)');
    print('');
    print(parser.usage);
    exit(0);
  }

  final input = args['input'] as String?;
  final output = args['output'] as String?;

  if (input == null || output == null) {
    stderr.writeln('Error: --input and --output are required');
    stderr.writeln('\nUsage: dart run bin/preprocess.dart [options]');
    stderr.writeln(parser.usage);
    exit(1);
  }

  final apiUrl = args['api-url'] as String;
  final apiModel = args['api-model'] as String;
  final chunkSize = int.parse(args['chunk-size'] as String);
  final chunkOverlap = int.parse(args['chunk-overlap'] as String);
  final extensions = (args['extensions'] as String).split(',').map((e) => e.trim()).toList();
  final verbose = args['verbose'] as bool;

  void log(String message) {
    if (verbose) print(message);
  }

  // Collect files to process
  final inputPath = p.normalize(input);
  final files = <File>[];

  if (FileSystemEntity.isDirectorySync(inputPath)) {
    final dir = Directory(inputPath);
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        final ext = p.extension(entity.path).toLowerCase();
        if (extensions.contains(ext)) {
          files.add(entity);
        }
      }
    }
  } else if (FileSystemEntity.isFileSync(inputPath)) {
    files.add(File(inputPath));
  } else {
    stderr.writeln('Error: Input path does not exist: $inputPath');
    exit(1);
  }

  if (files.isEmpty) {
    stderr.writeln('Error: No files found matching extensions: $extensions');
    exit(1);
  }

  print('Found ${files.length} file(s) to process');
  for (final f in files) {
    log('  - ${f.path}');
  }

  // Check for large files
  for (final file in files) {
    final size = await file.length();
    if (size > maxFileSizeBytes) {
      stderr.writeln('WARNING: Large file detected: ${file.path}');
      stderr.writeln('  Size: ${(size / 1024 / 1024).toStringAsFixed(2)} MB');
      stderr.writeln('  Files > ${maxFileSizeBytes ~/ 1024 ~/ 1024} MB may cause memory issues.');
      stderr.writeln('  Consider splitting large files before processing.');
    }
  }

  // Initialize embedder with dimension validation
  print('Initializing embedder ($apiUrl, model: $apiModel)...');
  final embedder = HttpEmbedder(apiUrl: apiUrl, model: apiModel);

  try {
    await embedder.initialize();
    print('Embedder OK (dimensions: ${embedder.dimensions})');
  } on EmbedderException catch (e) {
    stderr.writeln('Error: $e');
    stderr.writeln('');
    stderr.writeln('Make sure Ollama is running: ollama serve');
    stderr.writeln('And the model is pulled: ollama pull $apiModel');
    exit(1);
  }

  final chunker = Chunker(chunkSize: chunkSize, chunkOverlap: chunkOverlap);
  final database = RagDatabase();

  print('Opening database at: $output');
  await database.open(output);

  // Process files
  var totalChunks = 0;
  var totalDocs = 0;

  for (final file in files) {
    final fileName = p.basename(file.path);
    print('\nProcessing: $fileName');

    String content;
    try {
      content = await file.readAsString();
    } catch (e) {
      stderr.writeln('  ERROR reading file: $e');
      continue;
    }

    log('  Content length: ${content.length} characters');

    final chunks = chunker.chunk(content);
    log('  Chunks: ${chunks.length}');

    if (chunks.isEmpty) {
      log('  Skipping (no content)');
      continue;
    }

    // Generate embeddings
    print('  Generating embeddings...');
    final embeddings = <List<double>>[];

    for (var i = 0; i < chunks.length; i++) {
      if (verbose || i % 10 == 0) {
        stdout.write('\r  Embedding chunk ${i + 1}/${chunks.length}...');
      }

      try {
        final embedding = await embedder.embed(chunks[i]);
        embeddings.add(embedding);
      } catch (e) {
        stderr.writeln('\n  ERROR generating embedding for chunk $i: $e');
        await embedder.close();
        await database.close();
        exit(1);
      }
    }
    print('\r  Embedded ${chunks.length} chunks                    ');

    // Store in database (uses transaction internally)
    await database.storeDocument(
      fileName: fileName,
      filePath: file.path,
      content: content,
      chunks: chunks,
      embeddings: embeddings,
      fileSize: content.length,
    );

    totalChunks += chunks.length;
    totalDocs++;
  }

  // Cleanup - close database and delete lock file for bundling
  await embedder.close();
  await database.close(cleanupLockFile: true);

  // Summary
  print('\n========================================');
  print('Preprocessing complete!');
  print('  Documents: $totalDocs');
  print('  Chunks: $totalChunks');
  print('  Output: $output');
  print('========================================');
  print('\nOutput files:');
  print('  $output/data.mdb  (bundle this with Flutter app)');
  print('  lock.mdb has been deleted (do NOT bundle it)');
  print('\nNext steps:');
  print('1. Copy $output/data.mdb to Flutter app assets/rag_db/');
  print('2. Update pubspec.yaml to include assets/rag_db/');
  print('3. Update rag_service.dart to extract and use pre-built database');
}
