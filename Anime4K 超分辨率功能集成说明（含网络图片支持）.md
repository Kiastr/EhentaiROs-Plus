# Anime4K 超分辨率功能集成说明

## 修改概览

本次修改在 Eros-FE 项目中集成了完整的 Anime4K 超分辨率功能，**同时支持本地图片和网络图片**，共涉及 **7 个文件**（2 个新建，5 个修改）。

---

## 新建文件

### 1. `lib/common/anime4k/anime4k_upscaler.dart`

**Anime4K 核心算法实现**，基于 Anime4K v1.0 "Push Pixels" 算法，纯 Dart 实现，无需 Native 依赖。

**算法流程：**

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 双线性插值放大 | 将图像放大到目标分辨率 |
| 2 | 计算亮度图 | 用于后续梯度和细化计算 |
| 3 | 线条细化（Unblur） | 将暗像素推向亮区域，细化动漫线条 |
| 4 | Sobel 梯度计算 | 检测图像边缘 |
| 5 | 梯度精炼 | 利用梯度信息将像素推向边缘，锐化细节 |

> 所有计算在 `compute()` 中执行，不阻塞 UI 线程。

---

### 2. `lib/common/anime4k/anime4k_service.dart`

**Anime4K 服务层**，提供文件缓存、防重复处理、本地文件处理和字节数据处理等功能。

**主要功能：**
- 单例模式（`Anime4KService.instance`）
- 基于文件路径/URL + 参数组合的磁盘缓存（存储于临时目录 `anime4k_cache/`）
- 防止同一图片重复处理的并发控制
- `processFile()` — 处理本地图片文件
- `processImage()` — 处理任意字节数据（供网络图片使用）
- 支持清除缓存和查询缓存大小

---

## 修改文件

### 3. `lib/models/eh_config.dart`

在 `EhConfig` 数据模型中新增 **5 个** Anime4K 配置字段，并同步更新了 `fromJson`、`toJson`、`clone`、`copyWith`、`==` 和 `hashCode`。

| 字段 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `enableAnime4K` | `bool?` | `false` | 是否对本地图片启用超分 |
| `anime4KScaleFactor` | `double?` | `2.0` | 放大倍数 |
| `anime4KPushStrength` | `double?` | `0.31` | 线条细化强度 |
| `anime4KPushGradStrength` | `double?` | `1.0` | 梯度精炼强度 |
| `enableAnime4KForNetwork` | `bool?` | `false` | **新增** 是否对网络图片也启用超分 |

---

### 4. `lib/common/service/ehsetting_service.dart`

在 `EhSettingService` 中新增 **5 个** Anime4K 响应式属性，并在 `_initEhConfig()` 中添加对应的持久化绑定（`everProfile`）。

新增属性：
- `enableAnime4K` — 本地图片超分开关
- `anime4KScaleFactor` — 放大倍数
- `anime4KPushStrength` — 线条细化强度
- `anime4KPushGradStrength` — 梯度精炼强度
- `enableAnime4KForNetwork` — **新增** 网络图片超分开关

---

### 5. `lib/pages/setting/read_setting_page.dart`

在阅读设置页面更新 **Anime4K 超分辨率** 设置区块，新增网络图片超分开关：

| 控件 | 说明 |
|------|------|
| **启用 Anime4K 超分辨率** | 主开关，控制本地图片超分（`enableAnime4K`） |
| **网络图片也进行超分** *(新增)* | 子开关，仅在主开关开启时显示，控制在线浏览时的网络图片超分（`enableAnime4KForNetwork`） |
| **放大倍数** | ActionSheet 选择器，选项：1.5x / 2.0x / 3.0x / 4.0x |
| **线条细化强度** | ActionSheet 选择器，选项：0.00 / 0.15 / 0.31 / 0.50 / 0.75 |
| **梯度精炼强度** | ActionSheet 选择器，选项：0.00 / 0.50 / 1.00 / 1.50 / 2.00 |

**Footer 说明文字**动态更新，根据当前开关状态显示：
- 关闭时：`关闭状态：图片以原始分辨率显示。`
- 开启本地超分 + 关闭网络超分：`已启用...仅对已下载的本地图片超分，网络图片不进行处理。`
- 开启本地超分 + 开启网络超分：`已启用...本地图片和网络图片均已开启超分。`

---

### 6. `lib/pages/image_view/view/view_image.dart`

集成完整的超分处理逻辑，新增方法并替换所有图片加载调用：

**新增成员变量：**
- `_networkUpscaledBytes` — 缓存网络图片超分结果的内存数据

**新增方法：**

| 方法 | 说明 |
|------|------|
| `fileImageWithAnime4K(path)` | 本地图片超分入口，通过 `FutureBuilder` 异步处理，处理期间显示原图 |
| `_buildMemoryImage(bytes)` | 从内存字节构建 `ExtendedImage.memory` Widget，保持手势和 Hero 动画兼容 |
| `_triggerNetworkImageUpscale(...)` *(新增)* | 网络图片超分触发器：从 `extended_image` 磁盘缓存读取字节，通过 `Anime4KService.processImage()` 处理，完成后 `setState` 切换显示 |

**网络图片超分工作流程：**

```
图片加载完成（onLoadCompleted）
    ↓
_triggerNetworkImageUpscale() 被调用
    ↓
getCachedImageFile(imageUrl) 读取 extended_image 磁盘缓存
    ↓
Anime4KService.processImage() 在 Isolate 中处理
    ↓
setState(() { _networkUpscaledBytes = result; })
    ↓
FutureBuilder 重建，_buildViewImageWidgetProvider 返回 _buildMemoryImage()
```

**处理期间**：显示原始网络图片（无感知切换）  
**处理完成后**：通过 `setState` 无缝切换为超分结果

**本地图片替换点（共 8 处）：**

| 位置 | 原调用 | 新调用 |
|------|--------|--------|
| `build()` → `LoadFrom.download` | `fileImage(path)` | `fileImageWithAnime4K(path)` |
| `_buildViewImageWidget()` → `tempPath` | `fileImage(...)` | `fileImageWithAnime4K(...)` |
| `_buildViewImageWidget()` → FutureBuilder `filePath` | `fileImage(...)` | `fileImageWithAnime4K(...)` |
| `_buildViewImageWidget()` → FutureBuilder `tempPath` | `fileImage(...)` | `fileImageWithAnime4K(...)` |
| `_buildViewImageWidgetProvider()` → `filePath` | `fileImage(...)` | `fileImageWithAnime4K(...)` |
| `_buildViewImageWidgetProvider()` → `tempPath` | `fileImage(...)` | `fileImageWithAnime4K(...)` |
| `archiverImage()` → `file.path` | `fileImage(...)` | `fileImageWithAnime4K(...)` |
| `_buildDownloadImage()` → `tempPath` | `fileImage(...)` | `fileImageWithAnime4K(...)` |

---

### 7. `lib/common/global.dart`

在 `Global.init()` 中添加 `Anime4KService.instance.init()` 调用，确保应用启动时初始化超分缓存目录。

---

## 使用说明

1. 进入 **阅读设置** 页面
2. 找到 **Anime4K 超分辨率** 区块
3. 打开 **启用 Anime4K 超分辨率** 开关（本地图片超分）
4. 如需对在线浏览的网络图片也超分，打开 **网络图片也进行超分** 开关
5. 根据需要调整放大倍数、线条细化强度和梯度精炼强度

> **注意：** 网络图片超分在图片加载完成后异步触发，处理期间显示原始图片，完成后无缝切换为超分结果。超分结果会被缓存，相同图片+参数组合只处理一次。

---

## 性能建议

| 设备性能 | 推荐放大倍数 | 网络图片超分 |
|----------|-------------|-------------|
| 高端设备 | 3.0x ~ 4.0x | 可开启 |
| 中端设备 | 2.0x | 谨慎开启（会增加内存和处理时间） |
| 低端设备 | 1.5x | 建议关闭（仅开启本地图片超分） |
