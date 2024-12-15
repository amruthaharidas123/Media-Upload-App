import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';

class MediaUploadScreen extends StatefulWidget {
  const MediaUploadScreen({super.key});
  @override
  State<MediaUploadScreen> createState() => _MediaUploadScreenState();
}

class _MediaUploadScreenState extends State<MediaUploadScreen> {
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  String? _filePath;
  VideoPlayerController? _videoController;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  List<Map<String, String>> _uploadedVideos = [];
  String? _thumbnailPath;
  @override
  void initState() {
    super.initState();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initializationSettings =
        InitializationSettings(android: androidSettings);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  void _showNotification(double progress) {
    final androidDetails = AndroidNotificationDetails(
      'upload_channel',
      'File Uploads',
      channelDescription: 'Displays progress for file uploads',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      showProgress: true,
      maxProgress: 100,
      progress: (progress * 100).toInt(),
    );

    _notificationsPlugin.show(
      0,
      'Uploading File',
      '${(progress * 100).toStringAsFixed(1)}% complete',
      NotificationDetails(android: androidDetails),
    );
  }

  Future<void> _pickAndUploadFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();

      if (result == null) return;

      final file = File(result.files.single.path!);
      final fileSize = await file.length();
      if (fileSize < 100 * 1024 * 1024) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File size must be at least 100MB.')),
        );
        return;
      }

      setState(() {
        _filePath = file.path;
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      if (_isVideo(file.path)) {
        await _generateVideoThumbnail(file);
        _initializeVideoController(file);
      } else if (!_isDocument(file.path)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Unsupported file type. Only videos and documents are allowed.')),
        );
        setState(() {
          _isUploading = false;
        });
        return;
      }

      await _uploadFile(file.path);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File uploaded successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  bool _isVideo(String path) {
    final extension = path.split('.').last.toLowerCase();
    return ['mp4', 'mov', 'avi'].contains(extension);
  }

  bool _isDocument(String path) {
    final extension = path.split('.').last.toLowerCase();
    return ['pdf', 'docx', 'txt'].contains(extension);
  }

  Future<void> _generateVideoThumbnail(File file) async {
    final thumbnail = await VideoThumbnail.thumbnailFile(
      video: file.path,
      thumbnailPath: (await getTemporaryDirectory()).path,
      imageFormat: ImageFormat.PNG,
    );

    setState(() {
      _thumbnailPath = thumbnail;
    });
  }

  void _initializeVideoController(File file) {
    _videoController = VideoPlayerController.file(file)
      ..initialize().then((_) {
        setState(() {});
      });
  }

  Future<void> _uploadFile(String filePath) async {
    final file = File(filePath);
    final fileName = file.path.split('/').last;
    final storageRef =
        FirebaseStorage.instance.ref().child('uploads/$fileName');
    final uploadTask = storageRef.putFile(file);

    uploadTask.snapshotEvents.listen((event) {
      final progress = event.bytesTransferred / event.totalBytes;
      setState(() {
        _uploadProgress = progress;
      });
      _showNotification(progress);
    });

    await uploadTask;
    _notificationsPlugin.cancel(0);

    setState(() {
      _uploadedVideos.add({
        'filePath': filePath,
        'thumbnailPath': _thumbnailPath!,
      });
    });
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Media Upload App',
          style: TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Color.fromARGB(255, 7, 17, 70),
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: ListView(
          children: [
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: _isUploading ? null : _pickAndUploadFile,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    Color.fromARGB(255, 7, 17, 70), // Set background color
                minimumSize:
                    Size(50, 60), // Set minimum size (width: 200, height: 50)
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(20), // Optional: Add border radius
                ),
              ),
              child: const Text(
                'Select and Upload File',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold), // Optional: Text color
              ),
            ),
            const SizedBox(height: 20),
            if (_isUploading)
              Column(
                children: [
                  LinearProgressIndicator(value: _uploadProgress),
                  const SizedBox(height: 10),
                  Text(
                      '${(_uploadProgress * 100).toStringAsFixed(1)}% uploaded'),
                ],
              ),
            const SizedBox(height: 20),
            if (_thumbnailPath != null &&
                _filePath != null &&
                _isVideo(_filePath!))
              Image.file(File(_thumbnailPath!), height: 150),
            const SizedBox(height: 20),
            if (_filePath != null && _isVideo(_filePath!))
              _videoController != null && _videoController!.value.isInitialized
                  ? Column(
                      children: [
                        AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                        IconButton(
                          icon: Icon(_videoController!.value.isPlaying
                              ? Icons.pause
                              : Icons.play_arrow),
                          onPressed: () {
                            setState(() {
                              if (_videoController!.value.isPlaying) {
                                _videoController!.pause();
                              } else {
                                _videoController!.play();
                              }
                            });
                          },
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
