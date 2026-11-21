import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../domain/books.dart';
import '../../domain/book_reader.dart';
import '../../infrastructure/epub/image_policy.dart';

/// Single decoder in flight; no encoded-image or whole-book image cache.
class BookImageDecoder {
  BookImageDecoder(
    this.source, {
    this.decodeValidated,
    this.maxDimension = 2048,
  }) : assert(maxDimension > 0 && maxDimension <= 2048);
  final BookNavigationSource source;
  final int maxDimension;
  final Future<ui.Image?> Function(BookImagePayload)? decodeValidated;
  Future<void> _tail = Future.value();
  int active = 0, peakActive = 0;
  Future<ui.Image?> load(ContentKey key, String id, bool Function() cancelled) {
    final task = _tail.then((_) async {
      if (cancelled()) return null;
      active++;
      if (active > peakActive) peakActive = active;
      try {
        final data = await source.image(key, id, cancelled: cancelled);
        if (data == null ||
            cancelled() ||
            data.bytes.length > 50 * 1024 * 1024) {
          return null;
        }
        final info = ImagePolicy.inspect(
          data.bytes.sublist(0, math.min(65536, data.bytes.length)),
        );
        if (!info.usable ||
            info.width != data.width ||
            info.height != data.height) {
          return null;
        }
        ui.Image? image;
        if (decodeValidated != null) {
          image = await decodeValidated!(data);
        } else {
          final factor = math.min(
            1.0,
            maxDimension / math.max(data.width, data.height),
          );
          final codec = await ui.instantiateImageCodec(
            data.bytes,
            targetWidth: math.max(1, (data.width * factor).floor()),
            targetHeight: math.max(1, (data.height * factor).floor()),
            allowUpscaling: false,
          );
          try {
            if (codec.frameCount != 1) return null;
            image = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }
        }
        if (cancelled() ||
            (image != null &&
                (image.width > maxDimension || image.height > maxDimension))) {
          image?.dispose();
          return null;
        }
        return image;
      } catch (_) {
        return null;
      } finally {
        active--;
      }
    });
    _tail = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }
}

class BookImageView extends StatefulWidget {
  const BookImageView({
    super.key,
    required this.block,
    required this.decoder,
    this.viewportHeight,
  });
  final BookBlock block;
  final BookImageDecoder? decoder;
  final double? viewportHeight;
  @override
  State<BookImageView> createState() => _BookImageViewState();
}

class _BookImageViewState extends State<BookImageView> {
  ui.Image? _image;
  int _generation = 0;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BookImageView old) {
    super.didUpdateWidget(old);
    if (old.block.key != widget.block.key ||
        old.block.resourceId != widget.block.resourceId ||
        old.decoder != widget.decoder) {
      _image?.dispose();
      _image = null;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final id = widget.block.resourceId, decoder = widget.decoder;
    if (id == null || decoder == null) {
      _loading = false;
      return;
    }
    _loading = true;
    final image = await decoder.load(
      widget.block.key,
      id,
      () => !mounted || generation != _generation,
    );
    if (!mounted || generation != _generation) {
      image?.dispose();
      return;
    }
    setState(() {
      _image = image;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _generation++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alternative = widget.block.alternative?.isNotEmpty == true
        ? widget.block.alternative!
        : 'Illustration sans description';
    if (_image == null) {
      final placeholder = Semantics(
        image: true,
        child: Text(
          _loading
              ? 'Chargement de l’illustration : $alternative'
              : 'Image indisponible : $alternative',
        ),
      );
      return widget.viewportHeight == null
          ? placeholder
          : SizedBox(
              height: widget.viewportHeight,
              child: SingleChildScrollView(child: placeholder),
            );
    }
    return Semantics(
      image: true,
      label: alternative,
      child: ExcludeSemantics(
        child: SizedBox(
          height: widget.viewportHeight ?? 240,
          child: RawImage(image: _image, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
