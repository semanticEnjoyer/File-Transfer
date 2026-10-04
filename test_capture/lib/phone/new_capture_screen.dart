import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/models.dart';
import '../core/theme.dart';
import 'phone_store.dart';

class NewCaptureScreen extends StatefulWidget {
  const NewCaptureScreen({super.key, required this.store});
  final PhoneStore store;

  @override
  State<NewCaptureScreen> createState() => _NewCaptureScreenState();
}

class _NewCaptureScreenState extends State<NewCaptureScreen> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _note = TextEditingController();
  late final TextEditingController _project;
  final _tags = TextEditingController();
  final List<String> _paths = [];
  Priority _priority = Priority.medium;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _project = TextEditingController(text: widget.store.lastProject);
    // Most of the time you come here to attach media, so open the gallery right away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickMedia());
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _project.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    try {
      final files = await _picker.pickMultipleMedia();
      if (files.isEmpty) return;
      setState(() => _paths.addAll(files.map((f) => f.path)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not open gallery: $e')));
    }
  }

  Future<void> _recordVideo() async {
    final f = await _picker.pickVideo(source: ImageSource.camera);
    if (f != null) setState(() => _paths.add(f.path));
  }

  Future<void> _takePhoto() async {
    final f = await _picker.pickImage(source: ImageSource.camera);
    if (f != null) setState(() => _paths.add(f.path));
  }

  Future<void> _save() async {
    if (_paths.isEmpty && _title.text.trim().isEmpty && _note.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add a screenshot, a title or a note first')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.store.addCapture(
        title: _title.text,
        note: _note.text,
        priority: _priority,
        project: _project.text,
        tags: _tags.text
            .split(RegExp(r'[,#]'))
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        sourcePaths: _paths,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saving failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final recent = widget.store.recentProjects;
    return Scaffold(
      appBar: AppBar(title: const Text('New capture')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(widget.store.isPaired ? 'Save & send to PC' : 'Save (send after pairing)'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _MediaGrid(
            paths: _paths,
            onAdd: _pickMedia,
            onRemove: (i) => setState(() => _paths.removeAt(i)),
          ),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
                onPressed: _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Photo')),
            TextButton.icon(
                onPressed: _recordVideo,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Video')),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Title',
              hintText: 'e.g. Shop button not responding',
            ),
          ),
          const SizedBox(height: 18),
          Text('Priority', style: tt.labelLarge),
          const SizedBox(height: 8),
          PriorityPicker(value: _priority, onChanged: (p) => setState(() => _priority = p)),
          const SizedBox(height: 18),
          TextField(
            controller: _project,
            decoration: const InputDecoration(
              labelText: 'Project / game',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
          ),
          if (recent.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final p in recent)
                ChoiceChip(
                  label: Text(p),
                  selected: _project.text == p,
                  onSelected: (_) => setState(() => _project.text = p),
                ),
            ]),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: _note,
            minLines: 4,
            maxLines: 12,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Notes',
              hintText: 'Steps to reproduce, expected vs actual, build number…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _tags,
            decoration: const InputDecoration(
              labelText: 'Tags (optional)',
              hintText: 'ui, crash, audio',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.paths, required this.onAdd, required this.onRemove});
  final List<String> paths;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
      itemCount: paths.length + 1,
      itemBuilder: (_, i) {
        if (i == paths.length) {
          return InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.primary, width: 1.5),
                color: cs.primaryContainer.withValues(alpha: 0.3),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_outlined, color: cs.primary, size: 30),
                const SizedBox(height: 4),
                Text(paths.isEmpty ? 'Add from gallery' : 'Add more',
                    style: TextStyle(color: cs.primary, fontSize: 12)),
              ]),
            ),
          );
        }
        final p = paths[i];
        final isVideo = mediaKindFor(p) == MediaKind.video;
        return Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: isVideo
                ? Container(
                    color: Colors.black,
                    child: const Icon(Icons.movie, color: Colors.white, size: 32))
                : Image.file(File(p), fit: BoxFit.cover, cacheWidth: 300),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: () => onRemove(i),
              child: Container(
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                padding: const EdgeInsets.all(3),
                child: const Icon(Icons.close, color: Colors.white, size: 16),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
