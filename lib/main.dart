import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(ECGMonitorApp());

class ECGMonitorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ECG Monitor',
      theme: ThemeData.dark(),
      home: ECGMonitorScreen(),
    );
  }
}

class ECGMonitorScreen extends StatefulWidget {
  @override
  _ECGMonitorScreenState createState() => _ECGMonitorScreenState();
}

class _ECGMonitorScreenState extends State<ECGMonitorScreen>
    with SingleTickerProviderStateMixin {
  BluetoothConnection? _connection;
  bool isConnected = false;
  bool isMonitoring = false;

  List<FlSpot> _ecgData = [];
  List<int> _rawECG = [];
  double _xValue = 0;
  double bpm = 0;

  final int _samplingRate = 100;

  StreamSubscription<Uint8List>? _dataSubscription;
  late AnimationController _animationController;
  late Animation<Color?> _bpmColorAnimation;

  // Filtering variables
  List<double> _filterWindow = [];
  final int _filterWindowSize = 5;

  @override
  void initState() {
    super.initState();
    _requestPermissions();

    _animationController = AnimationController(
      vsync: this,
      duration: Duration(seconds: 1),
    )..repeat(reverse: true);

    _bpmColorAnimation = ColorTween(
      begin: Colors.greenAccent,
      end: Colors.redAccent,
    ).animate(_animationController);
  }

  Future<void> _requestPermissions() async {
    await Permission.bluetooth.request();
    await Permission.bluetoothConnect.request();
    await Permission.bluetoothScan.request();
    await Permission.location.request();
  }

  Future<void> _connectToDevice() async {
    final devices = await FlutterBluetoothSerial.instance.getBondedDevices();

    BluetoothDevice? esp32;
    try {
      esp32 = devices.firstWhere((d) => d.name == "ECG_Monitor");
    } catch (e) {
      esp32 = null;
    }

    if (esp32 == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ESP32 not paired.')),
      );
      return;
    }

    BluetoothConnection.toAddress(esp32.address).then((conn) {
      _connection = conn;
      setState(() => isConnected = true);

      _dataSubscription = _connection!.input!.listen((Uint8List data) {
        final lines = utf8.decode(data).split('\n');
        for (String line in lines) {
          line = line.trim();
          if (line.isEmpty) continue;

          try {
            int value = int.parse(line);
            _processECGValue(value);
          } catch (_) {}
        }
      });
    }).catchError((e) {
      print('Connection error: $e');
    });
  }

  void _processECGValue(int value) {
    if (!isMonitoring) return;

    // Convert ADC to voltage
    double voltage = value.toDouble() / 4095.0 * 3.3;

    // Add to filter window
    _filterWindow.add(voltage);
    if (_filterWindow.length > _filterWindowSize) {
      _filterWindow.removeAt(0);
    }

    // Moving average filter
    double smoothed =
        _filterWindow.reduce((a, b) => a + b) / _filterWindow.length;

    // Adjust baseline to center the signal
    double displayValue = (smoothed - 1.5) * 2 + 1.5;

    _xValue += 1.0;

    if (_ecgData.length > 500) _ecgData.removeAt(0);
    _ecgData.add(FlSpot(_xValue, displayValue.clamp(0, 3.3)));
    _rawECG.add((smoothed * 1000).toInt());

    if (_rawECG.length > _samplingRate * 5) {
      _calculateBPM();
      _rawECG.clear();
    }

    setState(() {});
  }

  void _calculateBPM() {
    List<int> signal = _rawECG;
    List<int> peaks = [];

    for (int i = 1; i < signal.length - 1; i++) {
      if (signal[i] > signal[i - 1] &&
          signal[i] > signal[i + 1] &&
          signal[i] > 3000) {
        if (peaks.isEmpty || (i - peaks.last) > _samplingRate * 0.5) {
          peaks.add(i);
        }
      }
    }

    if (peaks.length >= 2) {
      double avgInterval = 0;
      for (int i = 1; i < peaks.length; i++) {
        avgInterval += (peaks[i] - peaks[i - 1]);
      }
      avgInterval /= (peaks.length - 1);
      bpm = 60 * _samplingRate / avgInterval;
    }
  }

  void _toggleMonitoring() {
    setState(() => isMonitoring = !isMonitoring);
  }

  @override
  void dispose() {
    _dataSubscription?.cancel();
    _connection?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Widget _buildMetricCard(String label, String value) {
    return AnimatedBuilder(
      animation: _bpmColorAnimation,
      builder: (context, child) {
        return Card(
          color: _bpmColorAnimation.value,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 16, color: Colors.black87)),
                SizedBox(height: 8),
                Text(
                  value,
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("ECG Monitor"),
        actions: [
          IconButton(
            icon: Icon(Icons.bluetooth),
            onPressed: _connectToDevice,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Expanded(
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: 3.3,
                  titlesData: FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: _ecgData,
                      isCurved: true,
                      color: Colors.greenAccent,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),
            _buildMetricCard("BPM", "${bpm.toStringAsFixed(0)}"),
            SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(isMonitoring ? Icons.pause : Icons.play_arrow),
              label: Text(isMonitoring ? "Stop" : "Start"),
              onPressed: _toggleMonitoring,
            ),
          ],
        ),
      ),
    );
  }
}
