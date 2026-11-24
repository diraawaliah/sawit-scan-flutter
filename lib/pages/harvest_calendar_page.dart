import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class HarvestCalendarPage extends StatefulWidget {
  const HarvestCalendarPage({super.key});

  @override
  State<HarvestCalendarPage> createState() => _HarvestCalendarPageState();
}

class _HarvestCalendarPageState extends State<HarvestCalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  List<dynamic> _schedules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
    _initCalendarData();
  }

  Future<void> _initCalendarData() async {
    // 1. Tampilkan cache lokal seketika (0 ms) agar responsif dan cepat
    final cached = await ApiService.getCachedSchedules();
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _schedules = cached;
        _isLoading = false;
      });
    }

    // 2. Fetch pembaruan dari server jika online di background
    _loadSchedules(showLoadingIfEmpty: cached.isEmpty);
  }

  Future<void> _loadSchedules({bool showLoadingIfEmpty = true}) async {
    if (showLoadingIfEmpty && _schedules.isEmpty) {
      setState(() => _isLoading = true);
    }
    try {
      final data = await ApiService.fetchSchedules();
      if (mounted) {
        setState(() {
          _schedules = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Cek apakah suatu tanggal di kalender memiliki jadwal panen/tanam
  List<dynamic> _getEventsForDay(DateTime day) {
    final formattedDay = DateFormat('yyyy-MM-dd').format(day);
    return _schedules.where((item) {
      return item['next_harvest_date'] == formattedDay ||
          item['first_harvest_date'] == formattedDay ||
          item['planting_date'] == formattedDay;
    }).toList();
  }

  void _showAddScheduleDialog() {
    final blockController = TextEditingController();
    String selectedVariety = 'Tenera';
    DateTime pickedPlantingDate = DateTime.now();
    int intervalDays = 14;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          // Hitung preview estimasi panen perdana (+30 bulan)
          final previewFirstHarvest = DateTime(
            pickedPlantingDate.year,
            pickedPlantingDate.month + 30,
            pickedPlantingDate.day,
          );

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tambah Jadwal Tanam & Estimasi Panen',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: blockController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Blok Kebun (misal: Blok A-12)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.grid_view),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedVariety,
                  decoration: const InputDecoration(
                    labelText: 'Varietas Bibit Sawit',
                    border: OutlineInputBorder(),
                  ),
                  items: ['Tenera', 'Dura', 'Psifera']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (val) => setModalState(() => selectedVariety = val!),
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tanggal Awal Tanam'),
                  subtitle: Text(DateFormat('dd MMMM yyyy').format(pickedPlantingDate)),
                  trailing: FilledButton.tonalIcon(
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: const Text('Pilih Tanggal'),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: pickedPlantingDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) {
                        setModalState(() => pickedPlantingDate = picked);
                      }
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.green.shade700),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Estimasi Panen Perdana (+30 Bulan):\n${DateFormat('dd MMMM yyyy').format(previewFirstHarvest)} (Rotasi $intervalDays hari)',
                          style: TextStyle(
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: () async {
                      if (blockController.text.trim().isEmpty) return;
                      final messenger = ScaffoldMessenger.of(this.context);
                      Navigator.pop(context);
                      await ApiService.createSchedule(
                        blockName: blockController.text.trim(),
                        variety: selectedVariety,
                        plantingDate: DateFormat('yyyy-MM-dd').format(pickedPlantingDate),
                        harvestIntervalDays: intervalDays,
                      );
                      _loadSchedules();
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Jadwal disimpan! Notifikasi pengingat H-3 & Hari-H aktif.'),
                          ),
                        );
                      }
                    },
                    child: const Text('Simpan & Aktifkan Notifikasi Panen'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kalender & Estimasi Panen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSchedules,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddScheduleDialog,
        icon: const Icon(Icons.add_alarm),
        label: const Text('Catat Tanam'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                TableCalendar(
                  firstDay: DateTime.utc(2015, 1, 1),
                  lastDay: DateTime.utc(2035, 12, 31),
                  focusedDay: _focusedDay,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  eventLoader: _getEventsForDay,
                  calendarStyle: CalendarStyle(
                    markerDecoration: BoxDecoration(
                      color: Colors.green.shade700,
                      shape: BoxShape.circle,
                    ),
                    todayDecoration: BoxDecoration(
                      color: Colors.orange.shade400,
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Colors.green.shade800,
                      shape: BoxShape.circle,
                    ),
                  ),
                  onDaySelected: (selectedDay, focusedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      const Text(
                        'Daftar Blok & Jadwal Panen Terdekat',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const Spacer(),
                      Text('${_schedules.length} Blok'),
                    ],
                  ),
                ),
                Expanded(
                  child: _schedules.isEmpty
                      ? const Center(
                          child: Text('Belum ada jadwal tanam.\nTekan "Catat Tanam" di bawah.'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                          itemCount: _schedules.length,
                          itemBuilder: (context, index) {
                            final item = _schedules[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green.shade100,
                                  child: Icon(Icons.eco, color: Colors.green.shade800),
                                ),
                                title: Text(
                                  '${item['block_name']} (${item['variety']})',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'Tanam: ${item['planting_date']}\n'
                                  'Panen Perdana: ${item['first_harvest_date']}\n'
                                  'Jadwal Panen Terdekat: ${item['next_harvest_date']}',
                                ),
                                isThreeLine: true,
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () async {
                                    await ApiService.deleteSchedule(item['id']);
                                    _loadSchedules();
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}