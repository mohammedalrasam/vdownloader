import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Video Downloader',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const BrowserPage(),
    );
  }
}

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> {
  InAppWebViewController? _webViewController;
  // لتخزين روابط الفيديو المكتشفة
  List<Map<String, String>> _detectedVideos = [];
  // حالة إظهار الزر العائم
  bool _showFab = false;
  // عنوان URL الافتراضي
  final String _initialUrl = "https://www.example.com"; // يمكنك تغييره

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("متصفح التحميل الآمن"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController?.reload(),
          ),
        ],
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(_initialUrl)),
        initialSettings: InAppWebViewSettings(
          // تفعيل التصفح الآمن
          safeBrowsingEnabled: true,
          // تفعيل اكتشاف التحميل
          useOnDownloadStart: true,
          // تفعيل JavaScript (ضروري لاكتشاف الفيديو)
          javaScriptEnabled: true,
          // السماح بتشغيل الفيديو تلقائياً (اختياري)
          mediaPlaybackRequiresUserGesture: false,
          // لتحسين الأداء
          useShouldInterceptRequest: true,
          // إعدادات أخرى
          transparentBackground: true,
          allowFileAccess: true,
          allowContentAccess: true,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller;
          // إضافة معالج JavaScript لاستقبال روابط الفيديو
          controller.addJavaScriptHandler(
            handlerName: 'videoDetected',
            callback: (args) {
              final videoData = jsonDecode(args[0]);
              final String url = videoData['url'];
              final String quality = videoData['quality'] ?? 'غير معروفة';
              
              // تجنب التكرار
              if (!_detectedVideos.any((v) => v['url'] == url)) {
                setState(() {
                  _detectedVideos.add({'url': url, 'quality': quality});
                  _showFab = true;
                });
                _showSnackBar("تم اكتشاف فيديو جديد بجودة $quality");
              }
            },
          );
        },
        onLoadStop: (controller, url) async {
          // حقن سكريبت JavaScript بعد اكتمال تحميل الصفحة
          await _injectVideoDetectionScript(controller);
        },
        onDownloadStartRequest: (controller, request) async {
          // التعامل مع روابط التحميل المباشرة (إذا تم النقر على رابط تحميل)
          _showSnackBar("بدء تحميل الملف: ${request.suggestedFilename}");
          _downloadFile(request.url.toString(), request.suggestedFilename ?? 'video.mp4');
        },
      ),
      floatingActionButton: _showFab
          ? FloatingActionButton.extended(
              onPressed: _showQualityBottomSheet,
              icon: const Icon(Icons.download),
              label: const Text("تحميل الفيديو"),
            )
          : null,
    );
  }

  // دالة حقن JavaScript لاكتشاف الفيديو
  Future<void> _injectVideoDetectionScript(InAppWebViewController controller) async {
    const String jsCode = """
      (function() {
        // دالة لإرسال رابط الفيديو إلى Flutter
        function sendVideoToFlutter(url, quality) {
          if (window.flutter_inappwebview) {
            window.flutter_inappwebview.callHandler('videoDetected', JSON.stringify({
              url: url,
              quality: quality || 'auto'
            }));
          }
        }

        // مراقبة عناصر الفيديو الحالية
        function checkExistingVideos() {
          const videos = document.querySelectorAll('video');
          videos.forEach(video => {
            if (video.src) {
              sendVideoToFlutter(video.src, video.getAttribute('data-quality'));
            }
            // البحث عن مصادر متعددة
            const sources = video.querySelectorAll('source');
            sources.forEach(source => {
              if (source.src) {
                sendVideoToFlutter(source.src, source.getAttribute('data-quality') || source.getAttribute('label'));
              }
            });
          });
        }

        // مراقبة التغييرات في DOM لاكتشاف الفيديوهات الجديدة
        const observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            if (mutation.addedNodes.length) {
              mutation.addedNodes.forEach(function(node) {
                if (node.nodeName === 'VIDEO') {
                  if (node.src) sendVideoToFlutter(node.src, node.getAttribute('data-quality'));
                  const sources = node.querySelectorAll('source');
                  sources.forEach(source => {
                    if (source.src) sendVideoToFlutter(source.src, source.getAttribute('data-quality'));
                  });
                }
              });
            }
          });
        });

        observer.observe(document.body, { childList: true, subtree: true });

        // فحص أولي
        checkExistingVideos();
      })();
    """;
    await controller.evaluateJavascript(source: jsCode);
  }

  // عرض قائمة الجودات المتاحة
  void _showQualityBottomSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "اختر جودة التحميل",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ..._detectedVideos.map((video) {
                return ListTile(
                  leading: const Icon(Icons.video_file),
                  title: Text(video['quality'] ?? 'جودة غير معروفة'),
                  subtitle: Text(
                    video['url']!.length > 50
                        ? '${video['url']!.substring(0, 50)}...'
                        : video['url']!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _downloadFile(video['url']!, 'video_${DateTime.now().millisecondsSinceEpoch}.mp4');
                  },
                );
              }).toList(),
              if (_detectedVideos.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text("لا توجد فيديوهات مكتشفة حالياً"),
                ),
            ],
          ),
        );
      },
    );
  }

  // دالة التحميل
  Future<void> _downloadFile(String url, String fileName) async {
    // طلب إذن التخزين
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        _showSnackBar("يجب منح إذن التخزين للتحميل");
        return;
      }
    }

    try {
      final dir = await getExternalStorageDirectory();
      final savePath = "${dir!.path}/$fileName";

      _showSnackBar("جاري التحميل...");

      await Dio().download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total * 100).toStringAsFixed(0);
            // يمكنك تحديث واجهة التقدم هنا
          }
        },
      );

      _showSnackBar("تم التحميل بنجاح: $savePath");
    } catch (e) {
      _showSnackBar("فشل التحميل: $e");
    }
  }

  // دالة مساعدة لعرض رسائل SnackBar
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}