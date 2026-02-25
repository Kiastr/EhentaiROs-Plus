import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:eros_fe/common/anime4k/anime4k_service.dart';
import 'package:eros_fe/common/service/ehsetting_service.dart';
import 'package:eros_fe/component/exception/error.dart';
import 'package:eros_fe/const/const.dart';
import 'package:eros_fe/models/base/eh_models.dart';
import 'package:eros_fe/network/app_dio/pdio.dart';
import 'package:eros_fe/pages/image_view/controller/view_state.dart';
import 'package:eros_fe/utils/logger.dart';
import 'package:eros_fe/utils/utility.dart';
import 'package:eros_fe/utils/vibrate.dart';
import 'package:eros_fe/widget/image/eh_cached_network_image.dart';
import 'package:eros_fe/widget/image/extended_saf_image_privider.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../controller/view_controller.dart';
import 'view_widget.dart';

typedef DoubleClickAnimationListener = void Function();

class ViewImage extends StatefulWidget {
  const ViewImage({
    super.key,
    required this.imageSer,
    this.initialScale = 1.0,
    this.enableDoubleTap = true,
    this.mode = ExtendedImageMode.gesture,
    this.enableSlideOutPage = true,
    this.imageSizeChanged,
  });

  final int imageSer;
  final double initialScale;
  final bool enableDoubleTap;
  final ExtendedImageMode mode;
  final bool enableSlideOutPage;
  final ValueChanged<Size>? imageSizeChanged;

  @override
  State<ViewImage> createState() => _ViewImageState();
}

class _ViewImageState extends State<ViewImage> with TickerProviderStateMixin {
  final ViewExtController controller = Get.find();
  final EhSettingService ehSettingService = Get.find();

  late AnimationController _doubleClickAnimationController;
  Animation<double>? _doubleClickAnimation;
  late DoubleClickAnimationListener _doubleClickAnimationListener;

  late AnimationController _fadeAnimationController;

  /// 网络图片超分后的内存数据（null 表示未处理或未启用）
  Uint8List? _networkUpscaledBytes;

  ViewExtState get vState => controller.vState;

  bool get checkPHashHide => ehSettingService.enablePHashCheck;

  bool get checkQRCodeHide => ehSettingService.enableQRCodeCheck;

  @override
  void initState() {
    _doubleClickAnimationController = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);

    _fadeAnimationController = AnimationController(
        vsync: this, duration: Duration(milliseconds: vState.fade ? 200 : 0));
    vState.fade = true;

    if (vState.loadFrom == LoadFrom.gallery) {
      controller.initFuture(widget.imageSer);
    }

    if (vState.loadFrom == LoadFrom.archiver) {
      controller.initArchiveFuture(widget.imageSer);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.vState.fade = true;
      controller.vState.needRebuild = false;
    });

    vState.doubleTapScales[0] = widget.initialScale;

    super.initState();
  }

  @override
  void dispose() {
    _doubleClickAnimationController.dispose();
    _fadeAnimationController.dispose();
    _networkUpscaledBytes = null;
    super.dispose();
  }

  InitGestureConfigHandler get _initGestureConfigHandler =>
      (ExtendedImageState state) {
        final Size size = MediaQuery.of(context).size;
        double? initialScale = widget.initialScale;

        final imageInfo = state.extendedImageInfo;
        if (imageInfo != null) {
          initialScale = initScale(
              size: size,
              initialScale: initialScale,
              imageSize: Size(imageInfo.image.width.toDouble(),
                  imageInfo.image.height.toDouble()));

          vState.doubleTapScales[0] = initialScale ?? vState.doubleTapScales[0];
          vState.doubleTapScales[1] = initialScale != null
              ? initialScale * 2
              : vState.doubleTapScales[1];
        }
        return GestureConfig(
          inPageView: true,
          initialScale: initialScale ?? 1.0,
          maxScale: 10.0,
          // animationMaxScale: max(initialScale, 5.0),
          animationMaxScale: 10.0,
          initialAlignment: InitialAlignment.center,
          cacheGesture: false,
          hitTestBehavior: HitTestBehavior.opaque,
        );
      };

  /// 双击事件
  DoubleTap get _onDoubleTap => (ExtendedImageGestureState state) {
        ///you can use define pointerDownPosition as you can,
        ///default value is double tap pointer down position.
        final Offset? pointerDownPosition = state.pointerDownPosition;
        final double begin = state.gestureDetails?.totalScale ?? 0.0;
        double end;

        //remove old
        _doubleClickAnimation?.removeListener(_doubleClickAnimationListener);

        //stop pre
        _doubleClickAnimationController.stop();

        //reset to use
        _doubleClickAnimationController.reset();

        // logger.d('begin[$begin]  doubleTapScales[1]${doubleTapScales[1]}');

        if ((begin - vState.doubleTapScales[0]).abs() < 0.0005) {
          end = vState.doubleTapScales[1];
        } else if ((begin - vState.doubleTapScales[1]).abs() < 0.0005 &&
            vState.doubleTapScales.length > 2) {
          end = vState.doubleTapScales[2];
        } else {
          end = vState.doubleTapScales[0];
        }

        // logger.d('to Scales $end');

        _doubleClickAnimationListener = () {
          state.handleDoubleTap(
              scale: _doubleClickAnimation?.value ?? 1.0,
              doubleTapPosition: pointerDownPosition);
        };
        _doubleClickAnimation = _doubleClickAnimationController.drive(
            Tween<double>(begin: begin, end: end)
                .chain(CurveTween(curve: Curves.easeInOutCubic)));

        _doubleClickAnimation?.addListener(_doubleClickAnimationListener);

        _doubleClickAnimationController.forward();
      };

  @override
  Widget build(BuildContext context) {
    Widget image = () {
      logger.t('build image ${widget.imageSer}, loadFrom: ${vState.loadFrom}');
      switch (vState.loadFrom) {
        case LoadFrom.download:
          // 从已下载查看
          final path = vState.imagePathList[widget.imageSer - 1];
          return fileImageWithAnime4K(path);
        case LoadFrom.gallery:
          // 从画廊页查看
          return getViewImage();
        case LoadFrom.archiver:
          return archiverImage();
      }
    }();

    // return _image();

    return Obx(() {
      return HeroMode(
        enabled: widget.imageSer == controller.vState.currentItemIndex + 1,
        child: image,
      );
    });
  }

  /// 触发网络图片超分处理
  ///
  /// 图片加载完成后，尝试从 extended_image 缓存中读取字节数据，
  /// 再通过 Anime4K 处理，处理完成后通过 setState 更新显示。
  void _triggerNetworkImageUpscale({
    required String imageUrl,
    String? cacheKey,
  }) {
    if (!mounted) return;
    if (_networkUpscaledBytes != null) return; // 已处理过

    logger.d('Anime4K: 开始处理网络图片 $imageUrl');

    // 从 extended_image 缓存中获取字节数据
    Future<Uint8List?> _fetchImageBytes() async {
      // 尝试从磁盘缓存读取
      try {
        final cachedFile = await getCachedImageFile(imageUrl);
        if (cachedFile != null && await cachedFile.exists()) {
          return await cachedFile.readAsBytes();
        }
      } catch (e) {
        logger.w('Anime4K: 读取缓存文件失败: $e');
      }
      return null;
    }

    _fetchImageBytes().then((bytes) {
      if (bytes == null || !mounted) return;

      Anime4KService.instance.processImage(
        imageBytes: bytes,
        cacheKey: cacheKey ?? imageUrl,
        scaleFactor: ehSettingService.anime4KScaleFactor,
        pushStrength: ehSettingService.anime4KPushStrength,
        pushGradStrength: ehSettingService.anime4KPushGradStrength,
      ).then((result) {
        if (result != null && mounted) {
          logger.d('Anime4K: 网络图片超分完成 $imageUrl');
          setState(() {
            _networkUpscaledBytes = result;
          });
        }
      });
    });
  }

  /// Anime4K 超分辨率处理后的图片 Widget
  ///
  /// 如果 Anime4K 已启用，将异步处理图片并显示超分后的结果。
  /// 处理期间显示原始图片作为占位符。
  Widget fileImageWithAnime4K(String path) {
    if (!ehSettingService.enableAnime4K) {
      return fileImage(path);
    }

    return FutureBuilder<Uint8List?>(
      future: Anime4KService.instance.processFile(
        filePath: path,
        scaleFactor: ehSettingService.anime4KScaleFactor,
        pushStrength: ehSettingService.anime4KPushStrength,
        pushGradStrength: ehSettingService.anime4KPushGradStrength,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          // 超分处理完成，使用内存图片显示
          return _buildMemoryImage(snapshot.data!);
        }
        // 处理中显示原始图片
        return fileImage(path);
      },
    );
  }

  /// 从内存字节构建图片 Widget
  Widget _buildMemoryImage(Uint8List bytes) {
    final Size size = MediaQuery.of(context).size;

    Widget? loadStateChanged(ExtendedImageState state) {
      final ImageInfo? imageInfo = state.extendedImageInfo;
      widget.imageSizeChanged?.call(Size(
          imageInfo?.image.width.toDouble() ?? 0.0,
          imageInfo?.image.height.toDouble() ?? 0.0));
      if (state.extendedImageLoadState == LoadState.completed ||
          imageInfo != null) {
        controller.setScale100(imageInfo!, size);

        if (vState.imageSizeMap[widget.imageSer] == null) {
          vState.imageSizeMap[widget.imageSer] = Size(
              imageInfo.image.width.toDouble(),
              imageInfo.image.height.toDouble());
          Future.delayed(const Duration(milliseconds: 100)).then((value) =>
              controller.update(['$idImageListView${widget.imageSer}']));
        }

        controller.onLoadCompleted(widget.imageSer);

        return controller.vState.viewMode != ViewMode.topToBottom
            ? Hero(
                tag: '${widget.imageSer}',
                child: state.completedWidget,
                createRectTween: (Rect? begin, Rect? end) =>
                    MaterialRectCenterArcTween(begin: begin, end: end),
              )
            : state.completedWidget;
      } else if (state.extendedImageLoadState == LoadState.loading) {
        return ViewLoading(
          ser: widget.imageSer,
          duration: vState.viewMode != ViewMode.topToBottom
              ? const Duration(milliseconds: 100)
              : null,
          debugLabel: 'Anime4K 超分图片加载',
          label: 'Anime4K Upscaling ...',
        );
      }
      return null;
    }

    return ExtendedImage.memory(
      bytes,
      fit: BoxFit.contain,
      clearMemoryCacheWhenDispose: true,
      filterQuality: FilterQuality.medium,
      enableSlideOutPage: widget.enableSlideOutPage,
      mode: widget.mode,
      initGestureConfigHandler: _initGestureConfigHandler,
      onDoubleTap: widget.enableDoubleTap ? _onDoubleTap : null,
      loadStateChanged: loadStateChanged,
    );
  }

  /// 本地图片文件 构建 Widget
  Widget fileImage(String path) {
    final Size size = MediaQuery.of(context).size;

    Widget? loadStateChanged(ExtendedImageState state) {
      final ImageInfo? imageInfo = state.extendedImageInfo;
      widget.imageSizeChanged?.call(Size(
          imageInfo?.image.width.toDouble() ?? 0.0,
          imageInfo?.image.height.toDouble() ?? 0.0));
      if (state.extendedImageLoadState == LoadState.completed ||
          imageInfo != null) {
        // 加载完成 显示图片
        controller.setScale100(imageInfo!, size);

        // 重新设置图片容器大小
        if (vState.imageSizeMap[widget.imageSer] == null) {
          vState.imageSizeMap[widget.imageSer] = Size(
              imageInfo.image.width.toDouble(),
              imageInfo.image.height.toDouble());
          Future.delayed(const Duration(milliseconds: 100)).then((value) =>
              controller.update(['$idImageListView${widget.imageSer}']));
        }

        controller.onLoadCompleted(widget.imageSer);

        return controller.vState.viewMode != ViewMode.topToBottom
            ? Hero(
                tag: '${widget.imageSer}',
                child: state.completedWidget,
                createRectTween: (Rect? begin, Rect? end) =>
                    MaterialRectCenterArcTween(begin: begin, end: end),
              )
            : state.completedWidget;
      } else if (state.extendedImageLoadState == LoadState.loading) {
        // 显示加载中
        final ImageChunkEvent? loadingProgress = state.loadingProgress;
        final double? progress = loadingProgress?.expectedTotalBytes != null
            ? (loadingProgress?.cumulativeBytesLoaded ?? 0) /
                (loadingProgress?.expectedTotalBytes ?? 1)
            : null;

        return ViewLoading(
          ser: widget.imageSer,
          // progress: progress,
          duration: vState.viewMode != ViewMode.topToBottom
              ? const Duration(milliseconds: 100)
              : null,
          debugLabel: '### Widget fileImage 加载图片文件',
          label: 'Loading image file ...',
        );
      }
      return null;
    }

    return path.isContentUri
        ? ExtendedImage(
            image: ExtendedSafImageProvider(Uri.parse(path)),
            fit: BoxFit.contain,
            clearMemoryCacheWhenDispose: true,
            filterQuality: FilterQuality.medium,
            enableSlideOutPage: widget.enableSlideOutPage,
            mode: widget.mode,
            initGestureConfigHandler: _initGestureConfigHandler,
            onDoubleTap: widget.enableDoubleTap ? _onDoubleTap : null,
            loadStateChanged: loadStateChanged,
          )
        : ExtendedImage(
            image: ExtendedFileImageProvider(File(path)),
            fit: BoxFit.contain,
            clearMemoryCacheWhenDispose: true,
            filterQuality: FilterQuality.medium,
            enableSlideOutPage: widget.enableSlideOutPage,
            mode: widget.mode,
            initGestureConfigHandler: _initGestureConfigHandler,
            onDoubleTap: widget.enableDoubleTap ? _onDoubleTap : null,
            loadStateChanged: loadStateChanged,
          );
  }

  /// 归档页查看
  Widget archiverImage() {
    return FutureBuilder<File?>(
        future: controller.imageArchiveFutureMap[widget.imageSer],
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError || snapshot.data == null) {
              String errInfo = '';
              logger.e('${snapshot.error.runtimeType}');
              if (snapshot.error is EhError) {
                final EhError ehErr = snapshot.error as EhError;
                logger.e('$ehErr');
                errInfo = ehErr.type.toString();
                if (ehErr.type == EhErrorType.image509) {
                  return ViewErr509(ser: widget.imageSer);
                }
              } else if (snapshot.error is HttpException) {
                final HttpException e = snapshot.error as HttpException;
                if (e is BadRequestException && e.code == 429) {
                  return ViewErr429(ser: widget.imageSer);
                } else {
                  errInfo = e.message;
                }
              } else {
                logger.e(
                    'other error: ${snapshot.error}\n${snapshot.stackTrace}');
                errInfo = snapshot.error.toString();
              }

              if ((vState.errCountMap[widget.imageSer] ?? 0) <
                  vState.retryCount) {
                Future.delayed(const Duration(milliseconds: 100))
                    .then((_) => controller.initArchiveFuture(widget.imageSer));
                vState.errCountMap.update(
                    widget.imageSer, (int value) => value + 1,
                    ifAbsent: () => 1);

                logger.t('${vState.errCountMap}');
                logger.d(
                    '${widget.imageSer} 重试 第 ${vState.errCountMap[widget.imageSer]} 次');
              }
              if ((vState.errCountMap[widget.imageSer] ?? 0) >=
                  vState.retryCount) {
                return ViewError(ser: widget.imageSer, errInfo: errInfo);
              } else {
                return ViewLoading(
                  debugLabel: 'archiverImage 重试',
                  ser: widget.imageSer,
                  duration: vState.viewMode != ViewMode.topToBottom
                      ? const Duration(milliseconds: 50)
                      : null,
                );
              }
            }
            final File file = snapshot.data!;

            Widget image = fileImageWithAnime4K(file.path);

            return image;
          } else {
            return ViewLoading(
              ser: widget.imageSer,
              duration: vState.viewMode != ViewMode.topToBottom
                  ? const Duration(milliseconds: 50)
                  : null,
            );
          }
        });
  }

  /// 网络图片 （从画廊页查看）
  Widget getViewImage() {
    // 长按菜单
    return GetBuilder<ViewExtController>(
        id: '$idImageListView${widget.imageSer}',
        builder: (logic) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () async {
              logger.t('long press');
              vibrateUtil.medium();
              final GalleryImage? currentImage =
                  vState.pageState?.imageMap[widget.imageSer];

              logger.d('_currentImage ${currentImage?.toJson()}');

              // TODO(3003h): 对于已下载的图片，保存到相册时，从已下载读取.
              showImageSheet(
                context,
                () =>
                    controller.reloadImage(widget.imageSer, changeSource: true),
                imageUrl: currentImage?.imageUrl ?? '',
                filePath: currentImage?.filePath ?? currentImage?.tempPath,
                origImageUrl: currentImage?.originImageUrl,
                title: '${vState.pageState?.mainTitle} [${widget.imageSer}]',
                ser: widget.imageSer,
                gid: vState.pageState?.gid,
                filename: currentImage?.filename,
                isLocal: vState.loadFrom == LoadFrom.download ||
                    vState.loadFrom == LoadFrom.archiver,
              );
            },
            child: _buildViewImageWidgetProvider(),
          );
        });
  }

  Widget _buildViewImageWidget() {
    final GalleryImage? imageFromState =
        vState.pageState?.imageMap[widget.imageSer];
    logger.t('imageFromState ${imageFromState?.toJson()}');

    if (imageFromState?.hide ?? false) {
      return ViewAD(ser: widget.imageSer);
    }

    if ((imageFromState?.completeCache ?? false) &&
        !(imageFromState?.changeSource ?? false)) {
      // 图片文件已下载 加载显示本地图片文件
      if (imageFromState?.tempPath?.isNotEmpty ?? false) {
        logger.t('${widget.imageSer} filePath 不为空，加载图片文件');
        return fileImageWithAnime4K(imageFromState!.tempPath!);
      }

      if (imageFromState?.imageUrl != null &&
          (imageFromState?.downloadProcess == null)) {
        controller.downloadImage(
            ser: widget.imageSer,
            url: imageFromState!.imageUrl!,
            onError: (e) {
              _buildErr(e);
            });

        return _buildDownloadImage(debugLable: 'FutureBuilder 外');
      }
    }

    logger.d('return FutureBuilder ser:${widget.imageSer}');
    return FutureBuilder<GalleryImage?>(
        future: controller.imageFutureMap[widget.imageSer],
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.hasError || snapshot.data == null) {
              return _buildErr(snapshot.error);
            }
            final GalleryImage? imageData = snapshot.data;

            // 图片文件已下载 加载显示本地图片文件
            if (imageData?.filePath?.isNotEmpty ?? false) {
              logger.d('file... ${imageData?.filePath}');
              return fileImageWithAnime4K(imageData!.filePath!);
            }

            if (imageData?.tempPath?.isNotEmpty ?? false) {
              logger.d('file... ${imageData?.tempPath}');
              return fileImageWithAnime4K(imageData!.tempPath!);
            }

            if (imageData?.imageUrl != null) {
              logger.d('downloadImage...');

              controller.downloadImage(
                ser: widget.imageSer,
                url: imageData!.imageUrl!,
                reset: true,
              );
            }

            Widget image = _buildDownloadImage(debugLable: 'FutureBuilder内');

            return image;
          } else {
            return ViewLoading(
              debugLabel: 'FutureBuilder 加载画廊页数据',
              ser: widget.imageSer,
              duration: vState.viewMode != ViewMode.topToBottom
                  ? const Duration(milliseconds: 200)
                  : null,
            );
          }
        });
  }

  Widget _buildViewImageWidgetProvider() {
    final GalleryImage? imageFromState =
        vState.pageState?.imageMap[widget.imageSer];
    logger.d(
        'ser: ${widget.imageSer}, imageFromState ${imageFromState?.toJson()}');

    if (imageFromState?.hide ?? false) {
      return ViewAD(ser: widget.imageSer);
    }

    logger.t('return FutureBuilder ser:${widget.imageSer}');
    return FutureBuilder<GalleryImage?>(
        future: controller.imageFutureMap[widget.imageSer],
        builder: (context, snapshot) {
          logger.d(
              'FutureBuilder ser:${widget.imageSer}, snapshot.connectionState: ${snapshot.connectionState}');
          switch (snapshot.connectionState) {
            case ConnectionState.none:
            case ConnectionState.active:
            case ConnectionState.waiting:
              logger.d(
                  'FutureBuilder 加载画廊页数据 ser:${widget.imageSer}, snapshot.connectionState: ${snapshot.connectionState}');
              return ViewLoading(
                debugLabel: 'FutureBuilder 加载画廊页数据',
                ser: widget.imageSer,
                duration: vState.viewMode != ViewMode.topToBottom
                    ? const Duration(milliseconds: 200)
                    : null,
              );
            case ConnectionState.done:
              if (snapshot.hasError || snapshot.data == null) {
                logger.e('${snapshot.error}\n${snapshot.stackTrace}');
                return _buildErr(snapshot.error);
              }
              final GalleryImage? imageData = snapshot.data;

              final GalleryImage? currentImageData =
                  vState.pageState?.imageMap[widget.imageSer];

              logger.t('currentImageData ${currentImageData?.toJson()}\n'
                  'imageData        ${imageData?.toJson()}');

              // 图片文件已下载 加载显示本地图片文件
              if (imageData?.filePath?.isNotEmpty ?? false) {
                logger.d('图片文件已下载 file... ${imageData?.filePath}');
                controller.vState.galleryPageController?.uptImageBySer(
                  ser: widget.imageSer,
                  imageCallback: (image) => image.copyWith(
                    filePath: imageData?.filePath.oN,
                  ),
                );
                return fileImageWithAnime4K(imageData!.filePath!);
              }

              if (imageData?.tempPath?.isNotEmpty ?? false) {
                logger.t('tempPath file... ${imageData?.tempPath}');
                controller.vState.galleryPageController?.uptImageBySer(
                  ser: widget.imageSer,
                  imageCallback: (image) => image.copyWith(
                    tempPath: imageData?.tempPath.oN,
                  ),
                );
                return fileImageWithAnime4K(imageData!.tempPath!);
              }

              // 常规情况 加载网络图片
              // 图片加载完成
              void onLoadCompleted(ExtendedImageState state) {
                final ImageInfo? imageInfo = state.extendedImageInfo;
                controller.setScale100(imageInfo!, context.mediaQuerySize);

                widget.imageSizeChanged?.call(Size(
                    imageInfo.image.width.toDouble(),
                    imageInfo.image.height.toDouble()));

                if (imageData != null) {
                  final GalleryImage? tmpImage =
                      vState.imageMap?[imageData.ser];
                  if (tmpImage != null && !(tmpImage.completeHeight ?? false)) {
                    vState.galleryPageController?.uptImageBySer(
                      ser: imageData.ser,
                      imageCallback: (image) =>
                          image.copyWith(completeHeight: true.oN),
                    );

                    logger.t('upt _tmpImage ${tmpImage.ser}');
                    Future.delayed(const Duration(milliseconds: 100)).then(
                        (value) => controller.update(
                            [idSlidePage, '$idImageListView${imageData.ser}']));
                  }
                }

                controller.onLoadCompleted(widget.imageSer);
              }

              // if (kReleaseMode) {
              //   logger.d('ImageExt');
              //   return ImageExt(
              //     url: imageData?.imageUrl ?? '',
              //     onDoubleTap: widget.enableDoubleTap ? _onDoubleTap : null,
              //     ser: widget.imageSer,
              //     mode: widget.mode,
              //     enableSlideOutPage: widget.enableSlideOutPage,
              //     reloadImage: () =>
              //         controller.reloadImage(widget.imageSer, changeSource: true),
              //     fadeAnimationController: _fadeAnimationController,
              //     initGestureConfigHandler: _initGestureConfigHandler,
              //     onLoadCompleted: onLoadCompleted,
              //   );
              // }

              logger.t('ImageExtProvider, imageUrl: ${imageData?.imageUrl}');

              // 如果网络图片超分已完成，直接显示超分结果
              if (_networkUpscaledBytes != null) {
                return _buildMemoryImage(_networkUpscaledBytes!);
              }

              // 构建网络图片 Provider
              final networkProvider = ExtendedNetworkImageProvider(
                imageData?.imageUrl ?? '',
                timeLimit: const Duration(seconds: 5),
                cache: true,
                retries: 2,
                timeRetry: const Duration(seconds: 2),
                printError: true,
                cacheKey: imageData?.cacheKey,
              );

              // 如果启用了网络图片超分，包装 onLoadCompleted 以在加载完成后触发超分处理
              final wrappedOnLoadCompleted = ehSettingService.enableAnime4K &&
                      ehSettingService.enableAnime4KForNetwork
                  ? (ExtendedImageState state) {
                      onLoadCompleted(state);
                      _triggerNetworkImageUpscale(
                        imageUrl: imageData?.imageUrl ?? '',
                        cacheKey: imageData?.cacheKey,
                      );
                    }
                  : onLoadCompleted;

              Widget image = ImageExtProvider(
                image: ExtendedResizeImage.resizeIfNeeded(
                  provider: networkProvider,
                ),
                // image: getEhImageProvider(
                //   imageData?.imageUrl ?? '',
                //   ser: widget.imageSer,
                // ),
                // image: EhCheckHideImage(
                //   checkQRCodeHide: checkQRCodeHide,
                //   checkPHashHide: checkPHashHide,
                //   imageProvider: ExtendedNetworkImageProvider(
                //     imageData?.imageUrl ?? '',
                //     timeLimit: const Duration(seconds: 10),
                //     cache: true,
                //   ),
                // ),
                onDoubleTap: widget.enableDoubleTap ? _onDoubleTap : null,
                ser: widget.imageSer,
                mode: widget.mode,
                enableSlideOutPage: widget.enableSlideOutPage,
                reloadImage: () =>
                    controller.reloadImage(widget.imageSer, changeSource: true),
                fadeAnimationController: _fadeAnimationController,
                initGestureConfigHandler: _initGestureConfigHandler,
                onLoadCompleted: wrappedOnLoadCompleted,
              );

              return image;
          }
        });
  }

  Widget _buildErr(Object? e) {
    String errInfo = '';
    logger.e('${e.runtimeType}');
    if (e is DioException) {
      final DioException dioErr = e;
      logger.e('${dioErr.error}');
      errInfo = dioErr.type.toString();
    } else if (e is EhError) {
      final EhError ehErr = e;
      logger.e('$ehErr');
      errInfo = ehErr.type.toString();
      if (ehErr.type == EhErrorType.image509) {
        return ViewErr509(ser: widget.imageSer);
      }
    } else if (e is HttpException) {
      if (e is BadRequestException && e.code == 429) {
        return ViewErr429(ser: widget.imageSer);
      } else {
        errInfo = e.message;
      }
    } else {
      errInfo = e.toString();
    }

    if ((vState.errCountMap[widget.imageSer] ?? 0) < vState.retryCount) {
      Future.delayed(const Duration(milliseconds: 100)).then(
          (_) => controller.reloadImage(widget.imageSer, changeSource: true));
      vState.errCountMap
          .update(widget.imageSer, (int value) => value + 1, ifAbsent: () => 1);

      logger.t('${vState.errCountMap}');
      logger.d(
          '${widget.imageSer} 重试 第 ${vState.errCountMap[widget.imageSer]} 次');
    }
    if ((vState.errCountMap[widget.imageSer] ?? 0) >= vState.retryCount) {
      return ViewError(ser: widget.imageSer, errInfo: errInfo);
    } else {
      return ViewLoading(
        debugLabel: '重试',
        ser: widget.imageSer,
        duration: vState.viewMode != ViewMode.topToBottom
            ? const Duration(milliseconds: 100)
            : null,
      );
    }
  }

  Widget _buildDownloadImage({String? debugLable}) {
    if (kDebugMode && debugLable != null) {
      logger.d('_buildDownloadImage $debugLable');
    }
    return GetBuilder<ViewExtController>(
      id: '${idProcess}_${widget.imageSer}',
      builder: (controller) {
        final image = controller.vState.imageMap?[widget.imageSer];
        if (image == null) {
          return const SizedBox.shrink();
        }

        if (image.errorInfo?.isNotEmpty ?? false) {
          return ViewError(
            ser: widget.imageSer,
            errInfo: image.errorInfo,
          );
        }

        final process = image.downloadProcess ?? 0.0;
        if (process < 1.0) {
          return ViewLoading(
            ser: widget.imageSer,
            progress: process,
          );
        } else {
          return fileImageWithAnime4K(image.tempPath!);
        }
      },
    );
  }
}
