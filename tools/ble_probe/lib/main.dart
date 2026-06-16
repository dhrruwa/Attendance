import 'package:flutter/material.dart';

import 'advertiser_probe.dart';
import 'ble_permissions.dart';
import 'scanner_probe.dart';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BLE Probe',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const ProbeHome(),
      );
}

class ProbeHome extends StatefulWidget {
  const ProbeHome({super.key});
  @override
  State<ProbeHome> createState() => _ProbeHomeState();
}

class _ProbeHomeState extends State<ProbeHome> {
  final _logs = <String>[];
  final _observations = <ProbeObservation>[];

  late final AdvertiserProbe _advertiser = AdvertiserProbe(onLog: _log);
  late final ScannerProbe _scanner = ScannerProbe(
    onLog: _log,
    onObservation: (o) => setState(() {
      _observations.insert(0, o);
      if (_observations.length > 50) _observations.removeLast();
    }),
  );

  bool _permsOk = false;

  @override
  void initState() {
    super.initState();
    _ensurePerms();
  }

  Future<void> _ensurePerms() async {
    final ok = await BlePermissions.request();
    setState(() => _permsOk = ok);
    _log(ok
        ? 'Permissions granted.'
        : 'Permissions denied — grant in Settings.');
  }

  void _log(String m) => setState(() {
        _logs.insert(0, '${TimeOfDay.now().format(context)}  $m');
        if (_logs.length > 200) _logs.removeLast();
      });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Step-One BLE Probe'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Advertise', icon: Icon(Icons.wifi_tethering)),
            Tab(text: 'Scan', icon: Icon(Icons.bluetooth_searching)),
            Tab(text: 'Log', icon: Icon(Icons.list_alt)),
          ]),
          actions: [
            if (!_permsOk)
              IconButton(
                onPressed: _ensurePerms,
                icon: const Icon(Icons.lock_open),
                tooltip: 'Request permissions',
              ),
          ],
        ),
        body: TabBarView(
          children: [
            _advertiseTab(),
            _scanTab(),
            _logTab(),
          ],
        ),
      ),
    );
  }

  Widget _advertiseTab() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Run this on the TEACHER device. Advertises a value that rotates '
              'every 5s via local name + manufacturer data + GATT.',
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                title: const Text('Current value'),
                subtitle: Text(
                  _advertiser.currentValue.isEmpty
                      ? '—'
                      : _advertiser.currentValue,
                  style: const TextStyle(fontSize: 28),
                ),
                trailing: Icon(
                  _advertiser.isAdvertising
                      ? Icons.podcasts
                      : Icons.podcasts_outlined,
                  color: _advertiser.isAdvertising ? Colors.green : null,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                if (_advertiser.isAdvertising) {
                  await _advertiser.stop();
                } else {
                  await _advertiser.start();
                }
                setState(() {});
              },
              icon: Icon(
                  _advertiser.isAdvertising ? Icons.stop : Icons.play_arrow),
              label: Text(_advertiser.isAdvertising
                  ? 'Stop advertising'
                  : 'Start advertising'),
            ),
          ],
        ),
      );

  Widget _scanTab() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Run this on the STUDENT device. Each row shows which channel '
                    'carried the value across this OS combo.',
                  ),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    if (_scanner.isScanning) {
                      await _scanner.stop();
                    } else {
                      await _scanner.start(readGatt: true);
                    }
                    setState(() {});
                  },
                  icon: Icon(_scanner.isScanning
                      ? Icons.stop
                      : Icons.bluetooth_searching),
                  label: Text(_scanner.isScanning ? 'Stop' : 'Scan'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _observations.isEmpty
                ? const Center(child: Text('No observations yet.'))
                : ListView.separated(
                    itemCount: _observations.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final o = _observations[i];
                      return ListTile(
                        dense: true,
                        title: Text('RSSI ${o.rssi} dBm  ·  ${o.deviceId}'),
                        subtitle: Wrap(spacing: 8, children: [
                          _chip('name', o.localNameValue, o.gotLocalName),
                          _chip('mfg', o.manufacturerValue, o.gotManufacturer),
                          _chip('gatt', o.gattValue, o.gotGatt),
                        ]),
                      );
                    },
                  ),
          ),
        ],
      );

  Widget _chip(String label, String? value, bool ok) => Chip(
        visualDensity: VisualDensity.compact,
        backgroundColor: ok ? Colors.green.shade100 : Colors.red.shade100,
        label: Text('$label: ${value ?? '—'}'),
      );

  Widget _logTab() => ListView.builder(
        itemCount: _logs.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child:
              Text(_logs[i], style: const TextStyle(fontFamily: 'monospace')),
        ),
      );
}
