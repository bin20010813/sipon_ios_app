import 'package:flutter/material.dart';

class CheckInPage extends StatelessWidget {
  const CheckInPage({super.key});

  static const _bars = [
    _NearbyBar('庙前冰室（Hope & Sesame）', '黄浦区复兴中路 579', '450m', 4.9),
    _NearbyBar('Speak Low（彼楼）', '黄浦区复兴中路 579', '620m', 4.9),
    _NearbyBar('Janes and Hooch', '黄浦区巨鹿路 158', '1.1km', 4.5),
    _NearbyBar('Play House 电音夜店', '黄浦区淮海中路 333', '1.4km', 4.8),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFBF8F9),
    appBar: AppBar(
      title: const Text('打卡酒吧', style: TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        const Text(
          '附近酒吧',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF252229),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '选择本次到访的酒吧，记录今晚的感受。',
          style: TextStyle(color: Color(0xFF8F8790), fontSize: 13),
        ),
        const SizedBox(height: 16),
        for (final bar in _bars) _NearbyBarTile(bar: bar),
      ],
    ),
  );
}

class _NearbyBar {
  const _NearbyBar(this.name, this.address, this.distance, this.rating);
  final String name;
  final String address;
  final String distance;
  final double rating;
}

class _NearbyBarTile extends StatelessWidget {
  const _NearbyBarTile({required this.bar});
  final _NearbyBar bar;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: const BorderSide(color: Color(0xFFF0E9ED)),
    ),
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFEAD8),
        child: Icon(Icons.local_bar_rounded, color: Color(0xFFE08A3C)),
      ),
      title: Text(
        bar.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text('${bar.address}\n${bar.distance}  |  ${bar.rating} 分'),
      isThreeLine: true,
      trailing: FilledButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => _CheckInCommentPage(bar: bar),
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF9A3D78),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('打卡'),
      ),
    ),
  );
}

class _CheckInCommentPage extends StatefulWidget {
  const _CheckInCommentPage({required this.bar});
  final _NearbyBar bar;
  @override
  State<_CheckInCommentPage> createState() => _CheckInCommentPageState();
}

class _CheckInCommentPageState extends State<_CheckInCommentPage> {
  final _controller = TextEditingController();
  int _rating = 0;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_rating == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先给这家酒吧评分')));
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('打卡已记录')));
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFBF8F9),
    appBar: AppBar(
      title: const Text('记录打卡', style: TextStyle(fontWeight: FontWeight.w800)),
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bar.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF252229),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.bar.address,
            style: const TextStyle(color: Color(0xFF8F8790)),
          ),
          const SizedBox(height: 28),
          const Text('本次体验', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(
            children: [
              for (var index = 1; index <= 5; index++)
                IconButton(
                  onPressed: () => setState(() => _rating = index),
                  icon: Icon(
                    index <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFE09A35),
                    size: 30,
                  ),
                  tooltip: '$index 星',
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 5,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '写下这次的酒、音乐或遇见的人...',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(8)),
                borderSide: BorderSide(color: Color(0xFFF0E9ED)),
              ),
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_rounded),
              label: const Text('完成打卡'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF9A3D78),
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
