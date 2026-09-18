import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/drink_budget_store.dart';
import '../services/sipon_data_repository.dart';
import '../services/sipon_city_controller.dart';
import '../services/sticker_cutout_service.dart';
import '../widgets/drink_sticker.dart';
import '../widgets/sipon_city_picker.dart';
import 'language_transform.dart';

class DrinkRecordPage extends StatefulWidget {
  const DrinkRecordPage({super.key, this.onSaved});

  /// 接口接入点：保存时回调已收集的记账草稿。
  /// 当前未传入时，仅做本地校验与成功提示，不写接口。
  final ValueChanged<DrinkRecordDraft>? onSaved;

  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF252229);
  static const Color _muted = Color(0xFF8F8790);
  static const Color _line = Color(0xFFF0E7EE);
  static const Color _fieldBg = Color(0xFFFBF8FA);
  static const Color _chipBg = Color(0xFFFFF7FC);

  @override
  State<DrinkRecordPage> createState() => _DrinkRecordPageState();
}

class _DrinkRecordPageState extends State<DrinkRecordPage> {
  String? _drinkType;
  String? _place;
  String? _photoPath;
  String? _stickerImagePath;
  bool _isGeneratingSticker = false;
  int? _stickerColor;
  final TextEditingController _drinkNameController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  int _cups = 1;
  DateTime _date = DateTime.now();
  int _rating = 0;
  final TextEditingController _noteController = TextEditingController();

  @override
  void dispose() {
    _drinkNameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
  }

  Future<void> _pickPhoto() async {
    final action = await showModalBottomSheet<_PhotoSelectionAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final text = SiponLanguageScope.textOf(sheetContext);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PhotoActionTile(
                  icon: Icons.photo_camera_outlined,
                  label: text.t('拍照'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_PhotoSelectionAction.camera),
                ),
                _PhotoActionTile(
                  icon: Icons.photo_library_outlined,
                  label: text.t('从相册选择'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_PhotoSelectionAction.gallery),
                ),
                if (_photoPath != null)
                  _PhotoActionTile(
                    icon: Icons.hide_image_outlined,
                    label: text.t('移除照片'),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_PhotoSelectionAction.remove),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (action == null) return;

    if (action == _PhotoSelectionAction.remove) {
      if (mounted) {
        setState(() {
          _photoPath = null;
          _stickerImagePath = null;
        });
      }
      return;
    }

    final source = action == _PhotoSelectionAction.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _photoPath = picked.path;
      _stickerImagePath = null;
      _isGeneratingSticker = true;
    });

    try {
      final generated = await StickerCutoutService.instance.generate(
        picked.path,
      );
      if (!mounted) return;
      setState(() {
        _photoPath = generated.photoPath;
        _stickerImagePath = generated.stickerPath;
      });
      if (!generated.hasCutout) {
        final text = SiponLanguageScope.textOf(context);
        final message = switch (generated.status) {
          'unsupported' => text.t('当前系统暂不支持自动抠图，已保留原图'),
          'no_subject' => text.t('没有识别到清晰主体，已保留原图'),
          _ => text.t('自动抠图失败，已保留原图'),
        };
        _showMessage(message);
      }
    } on StickerCutoutException {
      if (mounted) {
        final text = SiponLanguageScope.textOf(context);
        _showMessage(text.t('自动抠图失败，已保留原图'));
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingSticker = false);
      }
    }
  }

  Future<void> _pickPlace() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _PlacePickerSheet(current: _place),
    );
    if (chosen != null && chosen.isNotEmpty && mounted) {
      setState(() => _place = chosen);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2018),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: DrinkRecordPage._brand,
              onPrimary: Colors.white,
            ),
            datePickerTheme: DatePickerThemeData(
              todayBorder: const BorderSide(
                color: DrinkRecordPage._brand,
                width: 1.5,
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    final text = SiponLanguageScope.textOf(context);

    if (_isGeneratingSticker) {
      _showMessage(text.t('贴纸正在生成，请稍候'));
      return;
    }

    if (_drinkType == null) {
      _showMessage(text.t('请选择酒款'));
      return;
    }
    if (_place == null) {
      _showMessage(text.t('请选择地点'));
      return;
    }

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showMessage(text.t('请填写花费金额'));
      return;
    }

    final drinkName = _drinkNameController.text.trim();
    final stickerColor =
        _stickerColor ?? drinkStickerColorForType(_drinkType!).toARGB32();
    final draft = DrinkRecordDraft(
      drinkType: _drinkType!,
      place: _place!,
      drinkName: drinkName,
      photoPath: _photoPath,
      stickerImagePath: _stickerImagePath,
      stickerColor: stickerColor,
      amount: amount,
      cups: _cups,
      date: _date,
      rating: _rating,
      note: _noteController.text.trim(),
    );

    final record = DrinkBudgetRecord(
      date: _date,
      amount: amount,
      drinkType: _drinkType!,
      place: _place!,
      drinkName: drinkName,
      photoPath: _photoPath,
      stickerImagePath: _stickerImagePath,
      stickerColor: stickerColor,
      tags: _tagsForDrinkType(_drinkType!),
      cups: _cups,
      rating: _rating,
      note: _noteController.text.trim(),
    );
    await DrinkBudgetStore.instance.addRecord(record);
    // 后台再做一次全量合并，把其他设备的记录拉下来。
    unawaited(DrinkBudgetStore.instance.ensureSynced());

    widget.onSaved?.call(draft);

    // addRecord 内部已尽力同步；仍有待同步记录说明当前离线，给个提示。
    _showMessage(
      DrinkBudgetStore.instance.hasPendingSync
          ? text.t('饮品贴纸已保存，待同步')
          : text.t('饮品贴纸已保存'),
    );
    _resetForm();
  }

  void _resetForm() {
    setState(() {
      _drinkType = null;
      _place = null;
      _photoPath = null;
      _stickerImagePath = null;
      _isGeneratingSticker = false;
      _stickerColor = null;
      _drinkNameController.clear();
      _amountController.clear();
      _cups = 1;
      _date = DateTime.now();
      _rating = 0;
      _noteController.clear();
    });
  }

  DrinkBudgetRecord get _previewRecord {
    final type = _drinkType ?? '鸡尾酒';
    return DrinkBudgetRecord(
      date: _date,
      amount: double.tryParse(_amountController.text.trim()) ?? 0,
      drinkType: type,
      place: _place ?? 'SipOn',
      drinkName: _drinkNameController.text.trim(),
      photoPath: _photoPath,
      stickerImagePath: _stickerImagePath,
      stickerColor: _stickerColor ?? drinkStickerColorForType(type).toARGB32(),
      cups: _cups,
      rating: _rating,
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    const ink = DrinkRecordPage._ink;
    const muted = DrinkRecordPage._muted;
    const brand = DrinkRecordPage._brand;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                  sliver: SliverList.list(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: IconButton.styleFrom(
                              fixedSize: const Size(42, 42),
                              backgroundColor: const Color(0xFFF8F3F7),
                              foregroundColor: ink,
                            ),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              text.t('记一笔'),
                              style: const TextStyle(
                                color: ink,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Text(
                        text.t('把这杯变成贴纸'),
                        style: const TextStyle(
                          color: ink,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        text.t('记录饮品、地点和花费，让本月月历慢慢长出你的微醺收藏。'),
                        style: const TextStyle(
                          color: muted,
                          fontSize: 14,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 22),
                      _StickerComposer(
                        record: _previewRecord,
                        photoPath: _photoPath,
                        stickerImagePath: _stickerImagePath,
                        isGenerating: _isGeneratingSticker,
                        onPickPhoto: _pickPhoto,
                      ),
                      const SizedBox(height: 18),
                      _TextInputTile(
                        icon: Icons.local_offer_outlined,
                        label: text.t('饮品名称'),
                        hintText: text.t('例如 Negroni / 拿铁 / IPA'),
                        controller: _drinkNameController,
                      ),
                      const SizedBox(height: 18),
                      _SectionLabel(text.t('酒款')),
                      const SizedBox(height: 12),
                      _DrinkTypeSelector(
                        selected: _drinkType,
                        onSelected: (value) => setState(() {
                          _drinkType = value;
                          _stickerColor = drinkStickerColorForType(
                            value,
                          ).toARGB32();
                        }),
                      ),
                      const SizedBox(height: 16),
                      _FieldTile(
                        icon: Icons.place_outlined,
                        label: text.t('地点'),
                        value: _place,
                        placeholder: text.t('选择酒吧'),
                        onTap: _pickPlace,
                      ),
                      const SizedBox(height: 10),
                      _AmountTile(controller: _amountController),
                      const SizedBox(height: 10),
                      _CupsTile(
                        cups: _cups,
                        onChanged: (value) => setState(() => _cups = value),
                      ),
                      const SizedBox(height: 10),
                      _FieldTile(
                        icon: Icons.calendar_today_outlined,
                        label: text.t('日期'),
                        value: _formatDate(_date, text),
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 10),
                      _RatingTile(
                        rating: _rating,
                        onChanged: (value) => setState(() => _rating = value),
                      ),
                      const SizedBox(height: 10),
                      _NoteTile(controller: _noteController),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isGeneratingSticker ? null : _save,
                        icon: const Icon(Icons.check_rounded),
                        label: Text(text.t('保存贴纸')),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: brand,
                          foregroundColor: Colors.white,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date, SiponAppText text) {
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) {
      return text.t('今天');
    }

    if (text.isZh) {
      return '${date.year}年${date.month}月${date.day}日';
    }

    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _StickerComposer extends StatelessWidget {
  const _StickerComposer({
    required this.record,
    required this.photoPath,
    required this.stickerImagePath,
    required this.isGenerating,
    required this.onPickPhoto,
  });

  final DrinkBudgetRecord record;
  final String? photoPath;
  final String? stickerImagePath;
  final bool isGenerating;
  final VoidCallback onPickPhoto;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final hasPhoto = photoPath != null && File(photoPath!).existsSync();
    final hasSticker =
        stickerImagePath != null && File(stickerImagePath!).existsSync();

    final title = isGenerating
        ? text.t('正在移除背景')
        : hasSticker
        ? text.t('透明贴纸已生成')
        : hasPhoto
        ? text.t('已保留原图')
        : text.t('先生成一枚贴纸');
    final description = isGenerating
        ? text.t('正在识别饮品主体，通常只需要几秒。')
        : hasSticker
        ? text.t('保存后会出现在月历和统计贴纸池。')
        : hasPhoto
        ? text.t('可以重新选择主体更清晰的照片。')
        : text.t('拍照或选择照片后，会自动移除背景并生成贴纸。');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8FC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFF0E7EE)),
      ),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: isGenerating
                ? const SizedBox(
                    key: ValueKey('processing'),
                    width: 86,
                    height: 86,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: DrinkRecordPage._brand,
                      ),
                    ),
                  )
                : DrinkSticker(
                    key: ValueKey(stickerImagePath ?? photoPath ?? 'default'),
                    record: record,
                    size: 86,
                    showLabel: true,
                    rotation: -0.08,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: DrinkRecordPage._ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: DrinkRecordPage._muted,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: isGenerating ? null : onPickPhoto,
                  icon: Icon(
                    hasPhoto
                        ? Icons.refresh_rounded
                        : Icons.add_photo_alternate_outlined,
                    size: 17,
                  ),
                  label: Text(text.t(hasPhoto ? '更换照片' : '添加照片')),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFFEDF7),
                    foregroundColor: DrinkRecordPage._brand,
                    disabledBackgroundColor: const Color(0xFFF1E8ED),
                    disabledForegroundColor: DrinkRecordPage._muted,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _PhotoSelectionAction { camera, gallery, remove }

class _PhotoActionTile extends StatelessWidget {
  const _PhotoActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: DrinkRecordPage._brand),
      title: Text(
        label,
        style: const TextStyle(
          color: DrinkRecordPage._ink,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _TextInputTile extends StatelessWidget {
  const _TextInputTile({
    required this.icon,
    required this.label,
    required this.hintText,
    required this.controller,
  });

  final IconData icon;
  final String label;
  final String hintText;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: DrinkRecordPage._fieldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DrinkRecordPage._line),
      ),
      child: Row(
        children: [
          Icon(icon, color: DrinkRecordPage._brand, size: 21),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: DrinkRecordPage._ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: DrinkRecordPage._ink,
                fontSize: 14,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  color: DrinkRecordPage._muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: DrinkRecordPage._ink,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _DrinkTypeSelector extends StatelessWidget {
  const _DrinkTypeSelector({required this.selected, required this.onSelected});

  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: [
        for (final option in _drinkOptions)
          _DrinkChip(
            label: text.t(option.key),
            icon: option.icon,
            selected: selected == option.key,
            onTap: () => onSelected(option.key),
          ),
      ],
    );
  }
}

class _DrinkChip extends StatelessWidget {
  const _DrinkChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? DrinkRecordPage._brand : DrinkRecordPage._chipBg,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: selected
                  ? DrinkRecordPage._brand
                  : const Color(0x229A3D78),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? Colors.white : DrinkRecordPage._brand,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF342C34),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.icon,
    required this.label,
    required this.value,
    this.placeholder,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? value;
  final String? placeholder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;

    return Material(
      color: DrinkRecordPage._fieldBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: DrinkRecordPage._line),
          ),
          child: Row(
            children: [
              Icon(icon, color: DrinkRecordPage._brand, size: 21),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: DrinkRecordPage._ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                hasValue ? value! : (placeholder ?? ''),
                style: TextStyle(
                  color: hasValue
                      ? DrinkRecordPage._ink
                      : DrinkRecordPage._muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: const Color(0xFFC7C1C6),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: DrinkRecordPage._fieldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DrinkRecordPage._line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.payments_outlined,
            color: DrinkRecordPage._brand,
            size: 21,
          ),
          const SizedBox(width: 10),
          Text(
            text.t('花费'),
            style: const TextStyle(
              color: DrinkRecordPage._ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          const Text(
            '¥',
            style: TextStyle(
              color: DrinkRecordPage._brand,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.end,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                color: DrinkRecordPage._ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: const TextStyle(
                  color: DrinkRecordPage._muted,
                  fontWeight: FontWeight.w700,
                ),
                border: InputBorder.none,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CupsTile extends StatelessWidget {
  const _CupsTile({required this.cups, required this.onChanged});

  final int cups;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: DrinkRecordPage._fieldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DrinkRecordPage._line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.timer_outlined,
            color: DrinkRecordPage._brand,
            size: 21,
          ),
          const SizedBox(width: 10),
          Text(
            text.t('杯数'),
            style: const TextStyle(
              color: DrinkRecordPage._ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          _Stepper(value: cups, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepperButton(
          icon: Icons.remove_rounded,
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 42,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: DrinkRecordPage._ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        _StepperButton(
          icon: Icons.add_rounded,
          onPressed: () => onChanged(value + 1),
        ),
        const SizedBox(width: 6),
        Text(
          text.t('杯'),
          style: const TextStyle(
            color: DrinkRecordPage._muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return Material(
      color: enabled ? DrinkRecordPage._brand : const Color(0xFFE6DDE3),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(
            icon,
            color: enabled ? Colors.white : const Color(0xFFB4ABB1),
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({required this.rating, required this.onChanged});

  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: DrinkRecordPage._fieldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DrinkRecordPage._line),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.star_outline_rounded,
            color: DrinkRecordPage._brand,
            size: 21,
          ),
          const SizedBox(width: 10),
          Text(
            text.t('评分'),
            style: const TextStyle(
              color: DrinkRecordPage._ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 1; index <= 5; index++)
                InkWell(
                  onTap: () => onChanged(index == rating ? 0 : index),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      index <= rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: index <= rating
                          ? const Color(0xFFFFB23C)
                          : const Color(0xFFCBC4C9),
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: DrinkRecordPage._fieldBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DrinkRecordPage._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_note_rounded,
                color: DrinkRecordPage._brand,
                size: 21,
              ),
              const SizedBox(width: 10),
              Text(
                text.t('备注'),
                style: const TextStyle(
                  color: DrinkRecordPage._ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(
              color: DrinkRecordPage._ink,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
            decoration: InputDecoration(
              hintText: text.t('添加备注'),
              hintStyle: const TextStyle(
                color: DrinkRecordPage._muted,
                fontWeight: FontWeight.w600,
              ),
              border: InputBorder.none,
              isCollapsed: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlacePickerSheet extends StatefulWidget {
  const _PlacePickerSheet({this.current});

  final String? current;

  @override
  State<_PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<_PlacePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<String> _places = _fallbackPlaces;
  bool _loading = true;
  String? _loadedCity;
  int _requestVersion = 0;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final city = SiponCityScope.controllerOf(context).city;
    if (city == _loadedCity) return;
    _loadedCity = city;
    _places = city == SiponCityController.defaultCity ? _fallbackPlaces : [];
    _loading = true;
    _loadPlaces(city);
  }

  @override
  void dispose() {
    _requestVersion++;
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPlaces(String city) async {
    final version = ++_requestVersion;
    try {
      final bars = await SiponDataRepository.instance.fetchHomeBars(city: city);
      if (mounted && version == _requestVersion) {
        setState(() {
          _places = bars.map((bar) => bar.name).toList();
          _loading = false;
        });
        return;
      }
    } catch (_) {}

    if (mounted && version == _requestVersion) {
      setState(() => _loading = false);
    }
  }

  List<String> get _filteredPlaces {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return _places;
    }

    return _places
        .where((place) => place.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  Future<void> _pickCustomPlace() async {
    final text = SiponLanguageScope.textOf(context);
    final customController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: Text(
            text.t('其他地点'),
            style: const TextStyle(
              color: DrinkRecordPage._ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          content: TextField(
            controller: customController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: text.t('输入自定义地点'),
              hintStyle: const TextStyle(
                color: DrinkRecordPage._muted,
                fontWeight: FontWeight.w600,
              ),
              filled: true,
              fillColor: DrinkRecordPage._fieldBg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: TextButton.styleFrom(
                foregroundColor: DrinkRecordPage._muted,
              ),
              child: Text(text.t('取消')),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(customController.text.trim()),
              style: FilledButton.styleFrom(
                backgroundColor: DrinkRecordPage._brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(text.t('确定')),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final filtered = _filteredPlaces;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('选择地点'),
              style: const TextStyle(
                color: DrinkRecordPage._ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: DrinkRecordPage._fieldBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: DrinkRecordPage._line),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    color: DrinkRecordPage._muted,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: DrinkRecordPage._ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: text.t('搜索酒吧'),
                        hintStyle: const TextStyle(
                          color: DrinkRecordPage._muted,
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DrinkRecordPage._brand,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    for (final place in filtered)
                      _PlaceTile(
                        place: text.t(place),
                        selected: place == widget.current,
                        onTap: () => Navigator.of(context).pop(place),
                      ),
                    _PlaceTile(
                      place: text.t('其他地点'),
                      selected: false,
                      trailing: const Icon(
                        Icons.add_rounded,
                        color: DrinkRecordPage._brand,
                        size: 20,
                      ),
                      onTap: _pickCustomPlace,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.place,
    required this.selected,
    this.trailing,
    required this.onTap,
  });

  final String place;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF1F8) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.local_bar_outlined,
                color: DrinkRecordPage._brand,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: DrinkRecordPage._ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (trailing != null)
                trailing!
              else if (selected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: DrinkRecordPage._brand,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class DrinkRecordDraft {
  const DrinkRecordDraft({
    required this.drinkType,
    required this.place,
    required this.drinkName,
    required this.photoPath,
    required this.stickerImagePath,
    required this.stickerColor,
    required this.amount,
    required this.cups,
    required this.date,
    required this.rating,
    required this.note,
  });

  final String drinkType;
  final String place;
  final String drinkName;
  final String? photoPath;
  final String? stickerImagePath;
  final int stickerColor;
  final double amount;
  final int cups;
  final DateTime date;
  final int rating;
  final String note;
}

class _DrinkOption {
  const _DrinkOption({required this.key, required this.icon});

  final String key;
  final IconData icon;
}

const List<_DrinkOption> _drinkOptions = [
  _DrinkOption(key: '鸡尾酒', icon: Icons.local_bar_outlined),
  _DrinkOption(key: '啤酒', icon: Icons.sports_bar_outlined),
  _DrinkOption(key: '威士忌', icon: Icons.liquor_outlined),
  _DrinkOption(key: '红酒', icon: Icons.wine_bar_outlined),
  _DrinkOption(key: '香槟', icon: Icons.celebration_outlined),
  _DrinkOption(key: '清酒', icon: Icons.local_drink_outlined),
  _DrinkOption(key: '烈酒', icon: Icons.flash_on_outlined),
  _DrinkOption(key: '咖啡', icon: Icons.coffee_outlined),
  _DrinkOption(key: '无酒精', icon: Icons.spa_outlined),
  _DrinkOption(key: '其他', icon: Icons.more_horiz_outlined),
];

List<String> _tagsForDrinkType(String type) {
  return switch (type) {
    '咖啡' => const ['咖啡因', '日间'],
    '无酒精' => const ['轻饮', '低负担'],
    '啤酒' => const ['精酿', '麦芽'],
    '威士忌' => const ['烈酒', '橡木'],
    '红酒' => const ['葡萄酒', '餐酒'],
    _ => const ['微醺'],
  };
}

const List<String> _fallbackPlaces = [
  '庙前冰室（Hope & Sesame）',
  'Speak Low（彼楼）',
  'Janes and Hooch',
  'Play House 电音夜店',
  '庙前酒馆',
  '天台酒廊',
  '巨鹿路小酒馆',
  '复兴公园酒廊',
  '思南精酿',
];
