import 'dart:math';

import 'package:flutter/material.dart';

enum Priority { low, medium, high, critical }

extension PriorityX on Priority {
  String get label => switch (this) {
        Priority.low => 'Low',
        Priority.medium => 'Medium',
        Priority.high => 'High',
        Priority.critical => 'Critical',
      };

  Color get color => switch (this) {
        Priority.low => const Color(0xFF4CAF50),
        Priority.medium => const Color(0xFF2196F3),
        Priority.high => const Color(0xFFFF9800),
        Priority.critical => const Color(0xFFE53935),
      };

  IconData get icon => switch (this) {
        Priority.low => Icons.keyboard_arrow_down,
        Priority.medium => Icons.drag_handle,
        Priority.high => Icons.keyboard_arrow_up,
        Priority.critical => Icons.priority_high,
      };
}

enum ItemStatus { open, inProgress, reported, done }

extension ItemStatusX on ItemStatus {
  String get label => switch (this) {
        ItemStatus.open => 'Open',
        ItemStatus.inProgress => 'In progress',
        ItemStatus.reported => 'Reported',
        ItemStatus.done => 'Done',
      };

  IconData get icon => switch (this) {
        ItemStatus.open => Icons.radio_button_unchecked,
        ItemStatus.inProgress => Icons.timelapse,
        ItemStatus.reported => Icons.outgoing_mail,
        ItemStatus.done => Icons.check_circle,
      };
}

enum MediaKind { image, video }

const _videoExt = {'mp4', 'mov', 'mkv', 'webm', '3gp', 'avi', 'm4v'};

MediaKind mediaKindFor(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
  return _videoExt.contains(ext) ? MediaKind.video : MediaKind.image;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

String newId() {
  final r = Random.secure();
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final rnd = List.generate(6, (_) => r.nextInt(36).toRadixString(36)).join();
  return '$ts$rnd';
}

/// Strips anything that is not safe in a file name.
String safeFileName(String name) {
  final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return 'file';
  return cleaned;
}

class MediaFile {
  MediaFile({
    required this.fileName,
    required this.kind,
    this.size = 0,
    this.uploaded = false,
  });

  /// File name inside the item's media folder (unique per item).
  final String fileName;
  final MediaKind kind;
  int size;

  /// Phone side only: has this file reached the PC.
  bool uploaded;

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'kind': kind.name,
        'size': size,
        'uploaded': uploaded,
      };

  factory MediaFile.fromJson(Map<String, dynamic> j) => MediaFile(
        fileName: j['fileName'] as String,
        kind: _enumByName(MediaKind.values, j['kind'], MediaKind.image),
        size: (j['size'] as num?)?.toInt() ?? 0,
        uploaded: j['uploaded'] as bool? ?? false,
      );
}

enum SyncState { pending, syncing, synced, failed }

class CaptureItem {
  CaptureItem({
    required this.id,
    required this.title,
    this.note = '',
    this.priority = Priority.medium,
    this.status = ItemStatus.open,
    this.project = '',
    List<String>? tags,
    List<MediaFile>? media,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.deviceName = '',
    this.complete = false,
    this.syncState = SyncState.pending,
    this.syncError,
  })  : tags = tags ?? [],
        media = media ?? [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String title;
  String note;
  Priority priority;
  ItemStatus status;
  String project;
  List<String> tags;
  List<MediaFile> media;
  final DateTime createdAt;
  DateTime updatedAt;
  String deviceName;

  /// Hub side: all media has arrived.
  bool complete;

  /// Phone side only.
  SyncState syncState;
  String? syncError;

  bool get hasVideo => media.any((m) => m.kind == MediaKind.video);
  MediaFile? get firstImage {
    for (final m in media) {
      if (m.kind == MediaKind.image) return m;
    }
    return null;
  }

  /// Fields shared between phone and PC.
  Map<String, dynamic> toWireJson() => {
        'id': id,
        'title': title,
        'note': note,
        'priority': priority.name,
        'status': status.name,
        'project': project,
        'tags': tags,
        'media': media
            .map((m) => {'fileName': m.fileName, 'kind': m.kind.name, 'size': m.size})
            .toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deviceName': deviceName,
      };

  Map<String, dynamic> toJson() => {
        ...toWireJson(),
        'media': media.map((m) => m.toJson()).toList(),
        'complete': complete,
        'syncState': syncState.name,
        'syncError': syncError,
      };

  factory CaptureItem.fromJson(Map<String, dynamic> j) => CaptureItem(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        note: j['note'] as String? ?? '',
        priority: _enumByName(Priority.values, j['priority'], Priority.medium),
        status: _enumByName(ItemStatus.values, j['status'], ItemStatus.open),
        project: j['project'] as String? ?? '',
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList(),
        media: (j['media'] as List?)
            ?.map((e) => MediaFile.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        deviceName: j['deviceName'] as String? ?? '',
        complete: j['complete'] as bool? ?? false,
        syncState: _enumByName(SyncState.values, j['syncState'], SyncState.pending),
        syncError: j['syncError'] as String?,
      );
}

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${t.day}.${t.month}.${t.year}';
}

String formatBytes(int b) {
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}
