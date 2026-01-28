import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:private_messaging/generated/l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';

// Colori teal per lo stile uniforme
const Color _tealLight = Color(0xFF3BA8B0);
const Color _tealDark = Color(0xFF145A60);

/// Icona share platform-specific (iOS usa ios_share, Android usa share)
IconData get _platformShareIcon => Platform.isIOS ? Icons.ios_share : Icons.share;

/// Schermo per visualizzare PDF cifrati con zoom e scroll
class PdfViewerScreen extends StatefulWidget {
  final Attachment attachment;
  final AttachmentService attachmentService;
  final String? currentUserId;
  final String? senderId;

  const PdfViewerScreen({
    Key? key,
    required this.attachment,
    required this.attachmentService,
    this.currentUserId,
    this.senderId,
  }) : super(key: key);

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  PdfController? _pdfController;
  bool _isLoading = true;
  String? _errorMessage;
  int _currentPage = 1;
  int _totalPages = 0;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      if (kDebugMode) print('📄 [PDF_VIEWER] Loading PDF: ${widget.attachment.fileName}');

      // 1. Download and decrypt PDF
      final decryptedBytes = await widget.attachmentService.downloadAndDecryptAttachment(
        widget.attachment,
        widget.currentUserId ?? '',
        widget.senderId ?? '',
        useThumbnail: false,
      );

      if (decryptedBytes == null) {
        throw Exception('Failed to download PDF');
      }

      // 2. Save to temporary file (pdfx requires a file path)
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${widget.attachment.fileName}');
      await file.writeAsBytes(decryptedBytes);

      if (kDebugMode) print('✅ [PDF_VIEWER] PDF saved to temp: ${file.path}');

      // 3. Initialize PDF controller
      final pdfDocument = PdfDocument.openFile(file.path);

      setState(() {
        _pdfController = PdfController(
          document: pdfDocument,
        );
        _isLoading = false;
      });

      // Get page count after document is loaded
      final document = await pdfDocument;
      setState(() {
        _totalPages = document.pagesCount;
      });

      if (kDebugMode) print('✅ [PDF_VIEWER] PDF loaded successfully: $_totalPages pages');
    } catch (e) {
      if (kDebugMode) print('❌ [PDF_VIEWER] Error loading PDF: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _isLoading = false;
          _errorMessage = l10n.pdfViewerLoadError(e.toString());
        });
      }
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_platformShareIcon, color: Colors.white),
            onPressed: () => _shareDocument(context),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_tealLight, _tealDark],
          ),
        ),
        child: Column(
          children: [
            // Spazio per AppBar
            const SizedBox(height: kToolbarHeight + 40),

            // Info documento (stile location sharing)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    widget.attachment.fileName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.lock, color: Colors.white70, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        '${l10n.mediaEncryptedE2E} • ${_formatFileSize(widget.attachment.fileSize)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                  if (_totalPages > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Pagina $_currentPage di $_totalPages',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // PDF content
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Future<void> _shareDocument(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            const SizedBox(width: 12),
            Text(l10n.mediaDownloadingDocument),
          ],
        ),
        backgroundColor: _tealLight,
        duration: const Duration(seconds: 10),
      ),
    );

    try {
      final bytes = await widget.attachmentService.downloadAndDecryptAttachment(
        widget.attachment,
        widget.currentUserId ?? '',
        widget.senderId ?? '',
      );

      if (bytes == null) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/${widget.attachment.fileName}');
      await tempFile.writeAsBytes(bytes);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      await Share.shareXFiles([XFile(tempFile.path)]);
    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
    }
  }

  Widget _buildBody() {
    final l10n = AppLocalizations.of(context)!;
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            Text(
              l10n.pdfViewerLoading,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadPdf,
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (_pdfController == null) {
      return Center(
        child: Text(
          l10n.pdfViewerCannotLoad,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }

    return PdfView(
      controller: _pdfController!,
      onPageChanged: (page) {
        setState(() {
          _currentPage = page;
        });
      },
      onDocumentLoaded: (document) {
        if (kDebugMode) print('📄 [PDF_VIEWER] Document loaded');
      },
      onDocumentError: (error) {
        if (kDebugMode) print('❌ [PDF_VIEWER] Document error: $error');
        final l10n = AppLocalizations.of(context)!;
        setState(() {
          _errorMessage = l10n.pdfViewerError(error.toString());
        });
      },
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
  }
}
