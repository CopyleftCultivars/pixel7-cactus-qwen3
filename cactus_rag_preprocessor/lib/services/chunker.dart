/// Text chunking service using soft-separator algorithm.
/// Finds nearest whitespace/newline to avoid splitting words mid-text.
class Chunker {
  final int chunkSize;
  final int chunkOverlap;

  /// Window to search for soft separator (percentage of chunkSize)
  static const double separatorSearchWindow = 0.15;

  Chunker({
    this.chunkSize = 512,
    this.chunkOverlap = 64,
  });

  /// Split content into overlapping chunks using soft-separator algorithm.
  /// Finds nearest whitespace/newline within a window to preserve word integrity.
  List<String> chunk(String content) {
    if (content.isEmpty) return [];

    final chunks = <String>[];
    final step = chunkSize - chunkOverlap;
    final searchWindow = (chunkSize * separatorSearchWindow).round();

    var start = 0;
    while (start < content.length) {
      // Calculate ideal end position
      var idealEnd = (start + chunkSize).clamp(0, content.length);

      // Find soft separator (nearest whitespace/newline before idealEnd)
      var end = idealEnd;
      if (idealEnd < content.length) {
        end = _findSoftSeparator(content, idealEnd, searchWindow);
      }

      final chunk = content.substring(start, end).trim();

      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      // Move to next chunk position, adjusting for actual chunk end
      final actualStep = end - start;
      start += (actualStep > chunkOverlap) ? actualStep - chunkOverlap : step;

      // If remaining text is smaller than overlap, we're done
      if (start >= content.length ||
          (content.length - start < chunkOverlap && chunks.isNotEmpty)) {
        break;
      }
    }

    return chunks;
  }

  /// Find the nearest soft separator (whitespace/newline) before idealEnd.
  /// Searches backwards within the window. Returns idealEnd if no separator found.
  int _findSoftSeparator(String content, int idealEnd, int window) {
    final searchStart = (idealEnd - window).clamp(0, content.length);

    // Search backwards from idealEnd for whitespace/newline
    for (var i = idealEnd - 1; i >= searchStart; i--) {
      final char = content[i];
      if (char == '\n' || char == '\r') {
        // Prefer breaking at newlines (paragraph boundaries)
        return i + 1;
      }
      if (char == ' ' || char == '\t') {
        // Break at whitespace (word boundaries)
        return i + 1;
      }
    }

    // No separator found in window, fall back to hard cut
    return idealEnd;
  }
}
