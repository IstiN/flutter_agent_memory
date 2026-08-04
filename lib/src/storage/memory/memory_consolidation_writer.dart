import 'dart:async';

import '../../models/consolidation_result.dart';
import '../kb_storage.dart';
import 'memory_revision_service.dart';

/// Writes the result of a consolidation run: the MEMORY.md summary and the
/// derived skill cards.
class MemoryConsolidationWriter {
  final KbStorage storage;
  final MemoryRevisionService revision;

  MemoryConsolidationWriter(this.storage, this.revision);

  Future<void> write(
    ConsolidationResult result, {
    String? expectedRevisionHash,
  }) async {
    await _writeSummary(result.summary, expectedRevisionHash);
    await _writeSkillCards(result.skills);
  }

  Future<void> _writeSummary(
    String content,
    String? expectedRevisionHash,
  ) async {
    if (expectedRevisionHash == null) {
      await storage.writeFile('MEMORY.md', content);
      return;
    }
    final ok = await revision.write(content, expectedRevisionHash);
    if (!ok) {
      throw ConcurrentRevisionException(
        'MEMORY.md was modified during consolidation.',
      );
    }
  }

  Future<void> _writeSkillCards(List<SkillCard> skills) async {
    await _clearSkills();
    for (var i = 0; i < skills.length; i++) {
      await _writeSkillCard(i, skills[i]);
    }
  }

  Future<void> _writeSkillCard(int index, SkillCard skill) async {
    final id = 'sk_${(index + 1).toString().padLeft(4, '0')}';
    final buffer = StringBuffer()
      ..writeln('---')
      ..writeln('id: $id')
      ..writeln('title: ${skill.title}')
      ..writeln('tags: ${skill.tags.join(', ')}')
      ..writeln('---')
      ..writeln()
      ..writeln(skill.instruction);
    await storage.writeFile('skills/$id.md', buffer.toString());
  }

  Future<void> _clearSkills() async {
    // Best-effort removal: storage backends may not support listing arbitrary
    // files, so we simply overwrite known skill slots with empty content for
    // backends that do. For file storage the old files remain; this is left as
    // a known limitation for non-file backends.
    for (var i = 1; i <= 9999; i++) {
      final id = 'sk_${i.toString().padLeft(4, '0')}';
      final path = 'skills/$id.md';
      if (await storage.readFile(path) == null) break;
      await storage.writeFile(path, '');
    }
  }
}
