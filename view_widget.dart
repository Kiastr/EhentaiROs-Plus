  ImageExtProvider({
    super.key,
    required this.image,
    required this.ser,
    required this.fadeAnimationController,
    required this.reloadImage,
    this.imageHeight,
    this.imageWidth,
    this.retryCount = 5,
    this.onLoadCompleted,
    required this.initGestureConfigHandler,
    required this.onDoubleTap,
    this.mode = ExtendedImageMode.none,
    this.enableSlideOutPage = false,
  });

  final ImageProvider image;
  final int ser;
  final AnimationController fadeAnimationController;
  final VoidCallback reloadImage;
  final double? imageHeight;
  final double? imageWidth;
  final int retryCount;
  final ValueChanged<ExtendedImageState>? onLoadCompleted;
  final InitGestureConfigHandler initGestureConfigHandler;
  final DoubleTap? onDoubleTap;
  final ExtendedImageMode mode;
  final bool enableSlideOutPage;

  final EhSettingService ehSettingService = Get.find();

  @override
  Widget build(BuildContext context) {
    return ExtendedImage(
      image: image,
      fit: BoxFit.contain,
      handleLoadingProgress: true,
      clearMemoryCacheIfFailed: true,
      enableSlideOutPage: enableSlideOutPage,
      mode: mode,
      initGestureConfigHandler: initGestureConfigHandler,
      onDoubleTap: onDoubleTap,
      loadStateChanged: (ExtendedImageState state) {
        logger.t(
            'loadStateChanged ser:$ser, state:${state.extendedImageLoadState}, image:$image');
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            fadeAnimationController.reset();
            final ImageChunkEvent? loadingProgress = state.loadingProgress;
            final double? progress = loadingProgress?.expectedTotalBytes != null
                ? (loadingProgress?.cumulativeBytesLoaded ?? 0) /
                    (loadingProgress?.expectedTotalBytes ?? 1)
                : null;

            return _ViewLoading(
              progress: progress,
              ser: ser,
              label: 'Loading from network ...',
            );

          case LoadState.completed:
            fadeAnimationController.forward();
            onLoadCompleted?.call(state);

            Widget image = controller.vState.viewMode != ViewMode.topToBottom
                ? Hero(
                    tag: '$ser',
                    child: state.completedWidget,
                    createRectTween: (Rect? begin, Rect? end) =>
                        MaterialRectCenterArcTween(begin: begin, end: end),
                  )
                : state.completedWidget;

            image = FadeTransition(
              opacity: fadeAnimationController,
              child: image,
            );

            return image;

          case LoadState.failed:
            fadeAnimationController.reset();

            // logger.d('Failed e: ${state.lastException}\n${state.lastStack}');

            bool reload = false;
            reload = (controller.vState.errCountMap[ser] ?? 0) < retryCount;
            if (reload) {
              Future.delayed(const Duration(milliseconds: 100))
                  .then((_) => reloadImage());
              controller.vState.errCountMap
                  .update(ser, (int value) => value + 1, ifAbsent: () => 1);
              logger.d('$ser 重试 第 ${controller.vState.errCountMap[ser]} 次');
            }

            if (reload) {
              // return const SizedBox.shrink();
              return _ViewLoading(ser: ser, label: 'Try reload ...');
            } else {
              return Container(
                alignment: Alignment.center,
                constraints: BoxConstraints(
                  maxHeight: context.width * 0.8,
                ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error,
                        size: 50,
                        color: Colors.red,
                      ),
                      const Text(
                        'Load image failed',
                        style: TextStyle(
                            fontSize: 10,
                            color: CupertinoColors.secondarySystemBackground),
                      ),
                      Text(
                        '${ser + 1}',
                        style: const TextStyle(
                            color: CupertinoColors.secondarySystemBackground),
                      ),
                    ],
                  ),
                  onTap: () {
                    // state.reLoadImage();
                    reloadImage();
                  },
                ),
              );
            }
        }
      },
    );
  }
}

class ImageWithHide extends StatefulWidget {
  const ImageWithHide({
    super.key,
    required this.url,
    required this.child,
    required this.ser,
    this.checkPHashHide = false,
    this.checkQRCodeHide = false,