import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../models/message.dart';
import '../services/attachment_service.dart';

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.attachment.fileName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_totalPages > 0)
              Text(
                'Pagina $_currentPage di $_totalPages',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(l10n.pdfViewerDocumentInfoTitle),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.pdfViewerDocumentName(widget.attachment.fileName)),
                      const SizedBox(height: 8),
                      Text(l10n.pdfViewerDocumentSize(_formatFileSize(widget.attachment.fileSize))),
                      const SizedBox(height: 8),
                      Text(l10n.pdfViewerDocumentPages(_totalPages.toString())),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.lock, size: 16, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(l10n.pdfViewerEncrypted),
                        ],
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.close),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
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
