import 'package:flutter/material.dart';

IconData getFileIcon(String fileName, {bool isDir = false}) {
  if (isDir) return Icons.folder;
  final ext = fileName.toLowerCase().split('.').lastOrNull ?? '';

  if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico'].contains(ext)) {
    return Icons.image;
  }
  if (ext == 'pdf') return Icons.picture_as_pdf;
  if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v'].contains(ext)) {
    return Icons.videocam;
  }
  if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a'].contains(ext)) {
    return Icons.audiotrack;
  }
  if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'].contains(ext)) {
    return Icons.archive;
  }
  if (['doc', 'docx', 'txt', 'rtf', 'odt'].contains(ext)) {
    return Icons.description;
  }
  if (['xls', 'xlsx', 'csv', 'ods'].contains(ext)) {
    return Icons.table_chart;
  }
  if (['ppt', 'pptx', 'odp'].contains(ext)) {
    return Icons.slideshow;
  }
  if (['exe', 'msi', 'app', 'dmg', 'deb', 'rpm', 'sh', 'bat'].contains(ext)) {
    return Icons.play_arrow;
  }
  if (['js', 'ts', 'html', 'css', 'py', 'java', 'cpp', 'c', 'go', 'rs', 'dart', 'json', 'xml'].contains(ext)) {
    return Icons.code;
  }
  return Icons.insert_drive_file;
}

Color getFileIconColor(String fileName, {bool isDir = false}) {
  if (isDir) return Colors.amber.shade700;
  final ext = fileName.toLowerCase().split('.').lastOrNull ?? '';

  if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'svg', 'webp', 'ico'].contains(ext)) {
    return Colors.green;
  }
  if (ext == 'pdf') return Colors.red;
  if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'webm', 'mkv', 'm4v'].contains(ext)) {
    return Colors.orange;
  }
  if (['mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a'].contains(ext)) {
    return Colors.purple;
  }
  if (['zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'].contains(ext)) {
    return Colors.brown;
  }
  if (['doc', 'docx', 'txt', 'rtf', 'odt'].contains(ext)) {
    return Colors.blue;
  }
  if (['xls', 'xlsx', 'csv', 'ods'].contains(ext)) {
    return Colors.green.shade700;
  }
  if (['ppt', 'pptx', 'odp'].contains(ext)) {
    return Colors.deepOrange;
  }
  if (['exe', 'msi', 'app', 'dmg', 'deb', 'rpm', 'sh', 'bat'].contains(ext)) {
    return Colors.pink;
  }
  if (['js', 'ts', 'html', 'css', 'py', 'java', 'cpp', 'c', 'go', 'rs', 'dart', 'json', 'xml'].contains(ext)) {
    return Colors.blueGrey;
  }
  return Colors.grey;
}
