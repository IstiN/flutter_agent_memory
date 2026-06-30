/// Extracts a JSON string that may be wrapped in markdown code fences.
String extractJsonFromMarkdown(String response) {
  var text = response.trim();
  if (text.startsWith('```json')) {
    text = text.substring(7);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
  } else if (text.startsWith('```')) {
    text = text.substring(3);
    if (text.endsWith('```')) text = text.substring(0, text.length - 3);
  }
  return text.trim();
}
