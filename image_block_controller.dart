
  Future<void> addCustomImageHide(String imageUrl, {Rect? sourceRect}) async {
    if (customBlockList.any((e) => e.imageUrl == imageUrl)) {
      return;
    }

    File? imageFile;
    if (await cachedImageExists(imageUrl)) {
      imageFile = await getCachedImageFile(imageUrl);
    }

    imageFile ??= await imageCacheManager().getSingleFile(imageUrl,
        headers: {'cookie': Global.profile.user.cookie});

    final data = imageFile.readAsBytesSync();
    final image = phash.getValidImage(data);

    // 如果提供了 sourceRect 参数，则裁剪图像
    Image processedImage = image;
    if (sourceRect != null) {
      processedImage = copyCrop(
        image,
        x: sourceRect.left.toInt(),
        y: sourceRect.top.toInt(),
        width: sourceRect.width.toInt(),
        height: sourceRect.height.toInt(),
      );
    }

    final pHash = phash.calculatePHash(processedImage);