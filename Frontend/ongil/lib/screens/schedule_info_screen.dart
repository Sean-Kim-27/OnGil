import 'package:flutter/material.dart';
import '../services/place_service.dart';
import 'ai_schedule_working.dart';

/// 장소 선택을 끝낸 뒤 스케줄 생성에 필요한 값들을 입력받는 화면.
///
/// trip_type은 직접 고르지 않고 시작~종료 날짜로 계산하고(_tripType),
/// companion_type은 항상 SOLO로 보냄(화면에서는 인원 수만 정함).
class ScheduleInfoScreen extends StatefulWidget {
  final List<RecommendedPlace> places;
  final PlaceAnchor anchor;

  const ScheduleInfoScreen({super.key, required this.places, required this.anchor});

  @override
  State<ScheduleInfoScreen> createState() => _ScheduleInfoScreenState();
}

class _ScheduleInfoScreenState extends State<ScheduleInfoScreen> {
  static const primaryColor = Color(0xFFC85A32);
  static const bgColor = Color(0xFFFAF7F2);

  late final TextEditingController _titleCtrl;
  String _mobilityMode = 'WALK'; // map_controller.dart 기존 코드로 확인된 값
  int _searchRadius = 3; // SearchRadiusKm enum: 3 또는 5만 허용
  final String _companionType = 'SOLO'; // 확인된 값만 사용
  int _companionCount = 1;

  DateTime _startDateTime = DateTime.now();
  late DateTime _endDateTime;

  // 시간은 무시하고 날짜만 비교해 몇 박인지 계산.
  int get _nights {
    final start = DateTime(_startDateTime.year, _startDateTime.month, _startDateTime.day);
    final end = DateTime(_endDateTime.year, _endDateTime.month, _endDateTime.day);
    final diff = end.difference(start).inDays;
    return diff > 0 ? diff : 0;
  }

  String get _tripType => _nights > 0 ? 'OVERNIGHT' : 'DAY_TRIP';

  String get _tripTypeLabel {
    if (_nights <= 0) return '당일치기';
    if (_nights == 1) return '1박 2일';
    return '$_nights박 ${_nights + 1}일';
  }

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: '${widget.anchor.title} 감성 당일치기');
    _endDateTime = _startDateTime.add(const Duration(hours: 6));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  String _fmt(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y.$m.$d  $hh:$mm';
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final base = isStart ? _startDateTime : _endDateTime;
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startDateTime = picked;
        if (!_endDateTime.isAfter(_startDateTime)) {
          _endDateTime = _startDateTime.add(const Duration(hours: 6));
        }
      } else {
        _endDateTime = picked;
      }
    });
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일정 제목을 입력해주세요')),
      );
      return;
    }
    if (!_endDateTime.isAfter(_startDateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('종료 시간은 시작 시간보다 늦어야 해요')),
      );
      return;
    }

    // 서버 검증: 숙소는 박 수(_nights)를 초과해 선택할 수 없음.
    final accommodations =
        widget.places.where((p) => p.rawCategory == 'accommodation').toList();
    if (accommodations.length > _nights) {
      final names = accommodations.map((p) => p.title).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$_tripTypeLabel 일정엔 숙소를 최대 $_nights곳까지만 고를 수 있어요 '
            '(현재 ${accommodations.length}곳: $names). 이전 화면에서 선택을 조정하거나 '
            '종료 날짜를 늘려주세요.',
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => AiScheduleWorking(
          places: widget.places,
          anchor: widget.anchor,
          title: title,
          mobilityMode: _mobilityMode,
          searchRadius: _searchRadius,
          tripType: _tripType,
          companionType: _companionType,
          companionCount: _companionCount,
          startDateTime: _startDateTime,
          endDateTime: _endDateTime,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Color(0xFF2C2825), size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '일정 정보 입력',
          style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const _SectionLabel('일정 제목'),
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                hintText: '예) 충주 감성 당일치기',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFEFEBE4)),
                ),
              ),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('이동수단'),
            Row(
              children: [
                Expanded(
                  child: _ChoiceChip(
                    label: '도보',
                    selected: _mobilityMode == 'WALK',
                    onTap: () => setState(() => _mobilityMode = 'WALK'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ChoiceChip(
                    label: '차량',
                    selected: _mobilityMode == 'CAR',
                    onTap: () => setState(() => _mobilityMode = 'CAR'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            const _SectionLabel('검색 반경'),
            Row(
              children: [3, 5] // 백엔드 SearchRadiusKm enum이 3, 5만 허용 (4는 422)
                  .map((km) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: _ChoiceChip(
                            label: '${km}km',
                            selected: _searchRadius == km,
                            onTap: () => setState(() => _searchRadius = km),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('시작 시간'),
            _DateTimeTile(label: _fmt(_startDateTime), onTap: () => _pickDateTime(isStart: true)),
            const SizedBox(height: 16),
            const _SectionLabel('종료 시간'),
            _DateTimeTile(label: _fmt(_endDateTime), onTap: () => _pickDateTime(isStart: false)),
            const SizedBox(height: 24),

            const _SectionLabel('여행 유형'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.route_outlined, size: 18, color: primaryColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _tripTypeLabel,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primaryColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const _SectionLabel('인원'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEFEBE4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '함께 가는 인원',
                    style: TextStyle(fontSize: 14, color: Color(0xFF8A827A)),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        color: primaryColor,
                        onPressed: _companionCount > 1
                            ? () => setState(() => _companionCount--)
                            : null,
                      ),
                      Text(
                        '$_companionCount명',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        color: primaryColor,
                        onPressed: _companionCount < 6
                            ? () => setState(() => _companionCount++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 0,
                ),
                child: const Text(
                  'AI 스케줄 생성하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF2C2825)),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _ChoiceChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFC85A32).withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFFC85A32) : const Color(0xFFEFEBE4),
            width: selected ? 1.3 : 1,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: disabled
                ? const Color(0xFFB8B0A6)
                : (selected ? const Color(0xFFC85A32) : const Color(0xFF2C2825)),
          ),
        ),
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _DateTimeTile({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEFEBE4)),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 18, color: Color(0xFFC85A32)),
            const SizedBox(width: 10),
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
