// AURA Music Player — Flutter
// Засновник: Артем Процьків | Dart / Flutter | iOS + Android

import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── COLORS ──────────────────────────────────────────────────────────────────

const kOrange   = Color(0xFFFF5722);
const kBg       = Color(0xFF0A0A0A);
const kCard     = Color(0xFF1C1C1E);
const kCard2    = Color(0xFF2C2C2E);
const kWhite    = Color(0xFFFFFFFF);
const kGrey     = Color(0xFF888888);
const kRed      = Color(0xFFFF453A);

// ─── MAIN ────────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final prefs = await SharedPreferences.getInstance();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PlayerState(prefs)),
        ChangeNotifierProvider(create: (_) => LibraryState(prefs)),
        ChangeNotifierProvider(create: (_) => AppSettings(prefs)),
      ],
      child: const AuraApp(),
    ),
  );
}

// ─── APP ─────────────────────────────────────────────────────────────────────

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AURA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(primary: kOrange),
      ),
      home: const SplashPage(),
    );
  }
}

// ─── MODELS ──────────────────────────────────────────────────────────────────

class Track {
  final int    id;
  final String title;
  final String artist;
  final String album;
  final int    albumId;
  final int    duration;
  final String path;
  bool         fav;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.albumId,
    required this.duration,
    required this.path,
    this.fav = false,
  });

  String get durationStr {
    final s = duration ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  factory Track.from(SongModel s) => Track(
    id:       s.id,
    title:    s.title,
    artist:   s.artist    ?? 'Невідомий',
    album:    s.album     ?? 'Невідомий альбом',
    albumId:  s.albumId   ?? 0,
    duration: s.duration  ?? 0,
    path:     s.data,
  );
}

// ─── PLAYER STATE ─────────────────────────────────────────────────────────────

enum Repeat { off, all, one }

class PlayerState extends ChangeNotifier {
  PlayerState(this._prefs) { _setup(); }

  final SharedPreferences _prefs;
  final AudioPlayer _audio = AudioPlayer();

  List<Track> queue    = [];
  int         idx      = 0;
  Track?      current;
  bool        playing  = false;
  bool        shuffle  = false;
  Repeat      repeat   = Repeat.off;
  double      speed    = 1.0;
  Duration    pos      = Duration.zero;
  Duration    dur      = Duration.zero;
  Color       accent   = kOrange;

  // Sleep timer
  Timer?   _sleepTimer;
  Duration _sleepLeft = Duration.zero;
  bool     get sleepOn => _sleepTimer?.isActive == true;
  String   get sleepStr {
    final s = _sleepLeft.inSeconds;
    return '${(s ~/ 60).toString().padLeft(2,'0')}:${(s % 60).toString().padLeft(2,'0')}';
  }

  AudioPlayer get player => _audio;

  void _setup() {
    shuffle = _prefs.getBool('shuffle') ?? false;
    speed   = _prefs.getDouble('speed')  ?? 1.0;
    repeat  = Repeat.values[(_prefs.getInt('repeat') ?? 0).clamp(0, 2)];

    _audio.playingStream.listen((v) { playing = v; notifyListeners(); });
    _audio.positionStream.listen((v) { pos = v; notifyListeners(); });
    _audio.durationStream.listen((v) { dur = v ?? Duration.zero; notifyListeners(); });
    _audio.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) _onDone();
    });
    _audio.setSpeed(speed);
  }

  void _onDone() {
    switch (repeat) {
      case Repeat.one: _audio.seek(Duration.zero); _audio.play();
      case Repeat.all: _goto((idx + 1) % queue.length);
      case Repeat.off: if (idx < queue.length - 1) _goto(idx + 1);
    }
  }

  Future<void> open(List<Track> tracks, int i) async {
    queue = List.from(tracks);
    await _goto(i);
  }

  Future<void> _goto(int i) async {
    idx     = i.clamp(0, queue.length - 1);
    current = queue[idx];
    accent  = kOrange;
    notifyListeners();
    try {
      await _audio.setAudioSource(AudioSource.uri(Uri.file(current!.path)));
      await _audio.play();
    } catch (_) {}
  }

  Future<void> toggle()    async => playing ? _audio.pause() : _audio.play();
  Future<void> seekTo(Duration d) async => _audio.seek(d);

  Future<void> next() async {
    if (shuffle) {
      _goto(Random().nextInt(queue.length));
    } else {
      _goto((idx + 1) % queue.length);
    }
  }

  Future<void> prev() async {
    if (pos.inSeconds > 3) {
      _audio.seek(Duration.zero);
    } else if (shuffle) {
      _goto(Random().nextInt(queue.length));
    } else {
      _goto(idx > 0 ? idx - 1 : queue.length - 1);
    }
  }

  void setShuffle(bool v) {
    shuffle = v; _prefs.setBool('shuffle', v); notifyListeners();
  }

  void cycleRepeat() {
    repeat = Repeat.values[(repeat.index + 1) % 3];
    _prefs.setInt('repeat', repeat.index);
    notifyListeners();
  }

  Future<void> setSpeed(double v) async {
    speed = v.clamp(0.5, 2.0);
    await _audio.setSpeed(speed);
    _prefs.setDouble('speed', speed);
    notifyListeners();
  }

  void startSleep(Duration d) {
    _sleepTimer?.cancel();
    _sleepLeft = d;
    notifyListeners();
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_sleepLeft.inSeconds <= 1) {
        t.cancel(); _audio.pause(); _sleepLeft = Duration.zero;
      } else {
        _sleepLeft -= const Duration(seconds: 1);
      }
      notifyListeners();
    });
  }

  void cancelSleep() {
    _sleepTimer?.cancel(); _sleepLeft = Duration.zero; notifyListeners();
  }

  @override
  void dispose() { _audio.dispose(); _sleepTimer?.cancel(); super.dispose(); }
}

// ─── LIBRARY STATE ────────────────────────────────────────────────────────────

class LibraryState extends ChangeNotifier {
  LibraryState(this._prefs);

  final SharedPreferences _prefs;
  final OnAudioQuery      _query = OnAudioQuery();

  List<Track> tracks  = [];
  Set<int>    favIds  = {};
  bool        loading = false;

  List<Track> get favs => tracks.where((t) => t.fav).toList();

  Future<void> load() async {
    loading = true; notifyListeners();
    final saved = _prefs.getStringList('favs') ?? [];
    favIds = saved.map(int.parse).toSet();
    try {
      final songs = await _query.querySongs(
        sortType:  SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType:   UriType.EXTERNAL,
      );
      tracks = songs
          .where((s) => (s.duration ?? 0) >= 30000)
          .map(Track.from)
          .toList();
      for (final t in tracks) t.fav = favIds.contains(t.id);
    } catch (_) {}
    loading = false; notifyListeners();
  }

  void toggleFav(Track t) {
    t.fav = !t.fav;
    if (t.fav) favIds.add(t.id); else favIds.remove(t.id);
    _prefs.setStringList('favs', favIds.map((i) => '$i').toList());
    notifyListeners();
  }
}

// ─── SETTINGS STATE ───────────────────────────────────────────────────────────

class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs) {
    bass       = _prefs.getInt('bass')    ?? 0;
    eqPreset   = _prefs.getInt('eq')      ?? 0;
    proximity  = _prefs.getBool('prox')   ?? true;
    notifs     = _prefs.getBool('notifs') ?? true;
    crossfade  = _prefs.getBool('cross')  ?? false;
    carMode    = _prefs.getBool('car')    ?? false;
  }

  final SharedPreferences _prefs;

  int  bass      = 0;
  int  eqPreset  = 0;
  bool proximity = true;
  bool notifs    = true;
  bool crossfade = false;
  bool carMode   = false;

  void set(String k, dynamic v) {
    switch (k) {
      case 'bass':     bass      = v as int;  _prefs.setInt('bass', v);
      case 'eq':       eqPreset  = v as int;  _prefs.setInt('eq', v);
      case 'prox':     proximity = v as bool; _prefs.setBool('prox', v);
      case 'notifs':   notifs    = v as bool; _prefs.setBool('notifs', v);
      case 'cross':    crossfade = v as bool; _prefs.setBool('cross', v);
      case 'car':      carMode   = v as bool; _prefs.setBool('car', v);
    }
    notifyListeners();
  }
}

// ─── SPLASH PAGE ──────────────────────────────────────────────────────────────

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});
  @override State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double>   _s, _f;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _s = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));
    _f = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeIn));
    _c.forward();
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.audio.request();
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted) return;
    if (status.isGranted) {
      context.read<LibraryState>().load();
      _go();
    } else {
      await Permission.storage.request();
      context.read<LibraryState>().load();
      _go();
    }
  }

  void _go() {
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const HomePage()));
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: FadeTransition(opacity: _f,
          child: ScaleTransition(scale: _s,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [kOrange.withOpacity(0.9), Colors.transparent],
                  ),
                  boxShadow: [BoxShadow(color: kOrange.withOpacity(0.5),
                      blurRadius: 60, spreadRadius: 10)],
                ),
                child: const Icon(Icons.music_note_rounded, size: 64, color: kWhite),
              ),
              const SizedBox(height: 24),
              const Text('AURA',
                  style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900,
                      color: kWhite, letterSpacing: 10)),
              const SizedBox(height: 8),
              Text('Music Player',
                  style: TextStyle(fontSize: 15, color: kGrey, letterSpacing: 4)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── HOME PAGE ────────────────────────────────────────────────────────────────

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int    _tab   = 0;
  String _query = '';
  Timer? _st;

  List<Track> get _list {
    final lib = context.read<LibraryState>();
    final src = _tab == 1 ? lib.favs : lib.tracks;
    if (_query.isEmpty) return src;
    final q = _query.toLowerCase();
    return src.where((t) =>
    t.title.toLowerCase().contains(q) ||
        t.artist.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lib    = context.watch<LibraryState>();
    final player = context.watch<PlayerState>();

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        SafeArea(bottom: false, child: Column(children: [
          _header(),
          _searchBar(),
          _tabs(),
          Expanded(child: _trackList(lib, player)),
        ])),
        if (player.current != null)
          Positioned(
            left: 12, right: 12,
            bottom: MediaQuery.of(context).padding.bottom + 68,
            child: _MiniPlayer(onTap: () => _openPlayer()),
          ),
        Positioned(left: 0, right: 0, bottom: 0, child: _bottomNav()),
      ]),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
    child: Row(children: [
      const Text('Головна',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: kWhite)),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.sort_rounded, color: kGrey),
        onPressed: _sortSheet,
      ),
    ]),
  );

  Widget _searchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
    child: TextField(
      style: const TextStyle(color: kWhite),
      decoration: InputDecoration(
        hintText: 'Пошук...',
        hintStyle: TextStyle(color: kGrey),
        prefixIcon: const Icon(Icons.search, color: kGrey),
        filled: true,
        fillColor: kCard,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (v) {
        _st?.cancel();
        _st = Timer(const Duration(milliseconds: 250),
                () => setState(() => _query = v.trim()));
      },
    ),
  );

  Widget _tabs() {
    final tabs = ['Треки', 'Вибране', 'Плейлисти'];
    return SizedBox(height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: tabs.length,
        itemBuilder: (_, i) {
          final on = _tab == i;
          return GestureDetector(
            onTap: () => setState(() { _tab = i; _query = ''; }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: on ? kOrange : kCard,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tabs[i],
                  style: TextStyle(color: on ? kWhite : kGrey,
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          );
        },
      ),
    );
  }

  Widget _trackList(LibraryState lib, PlayerState player) {
    if (lib.loading) {
      return const Center(child: CircularProgressIndicator(color: kOrange));
    }
    final list = _list;
    if (list.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.library_music_rounded, size: 64,
            color: kGrey.withOpacity(0.4)),
        const SizedBox(height: 16),
        Text(_tab == 1 ? 'Немає вибраних' : 'Музику не знайдено',
            style: const TextStyle(color: kGrey)),
      ]));
    }
    return ListView.builder(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom +
            (player.current != null ? 160 : 80),
      ),
      itemCount: list.length,
      itemBuilder: (_, i) => _TrackTile(
        track: list[i],
        active: player.current?.id == list[i].id,
        onTap: () {
          player.open(list, i);
          _openPlayer();
        },
        onMore: () => _moreSheet(list[i]),
        onFav: () => lib.toggleFav(list[i]),
      ),
    );
  }

  Widget _bottomNav() {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          height: MediaQuery.of(context).padding.bottom + 64,
          decoration: BoxDecoration(
            color: kBg.withOpacity(0.85),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
          ),
          child: SafeArea(top: false,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navBtn(Icons.home_rounded, 'Головна', kOrange, () {}),
                _navBtn(Icons.settings_rounded, 'Налаштування', kGrey,
                        () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const SettingsPage()))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navBtn(IconData icon, String label, Color color, VoidCallback onTap) {
    return GestureDetector(onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(color: color, fontSize: 10)),
      ]),
    );
  }

  void _openPlayer() {
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, __, ___) => const PlayerPage(),
      transitionsBuilder: (_, a, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1), end: Offset.zero,
        ).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 380),
    ));
  }

  void _sortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _Sheet(title: 'Сортування', items: const [
        'По назві', 'По виконавцю', 'По альбому',
      ], onTap: (i) {
        Navigator.pop(context);
        context.read<LibraryState>().load();
      }),
    );
  }

  void _moreSheet(Track t) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
        _handle(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Row(children: [
            _ArtWidget(id: t.id, size: 48),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.title, style: const TextStyle(
                    color: kWhite, fontWeight: FontWeight.w700), maxLines: 1),
                Text(t.artist, style: const TextStyle(color: kGrey, fontSize: 12)),
              ],
            )),
          ]),
        ),
        const Divider(color: Colors.white10, height: 1),
        _sheetBtn(Icons.playlist_add_rounded, kOrange, 'Додати до плейлиста',
                () { Navigator.pop(context); }),
        _sheetBtn(Icons.equalizer_rounded, kWhite, 'Еквалайзер',
                () { Navigator.pop(context); }),
        _sheetBtn(Icons.share_rounded, kWhite, 'Поділитися',
                () { Navigator.pop(context); }),
        _sheetBtn(Icons.info_outline_rounded, kWhite, 'Інформація',
                () { Navigator.pop(context); _infoDialog(t); }),
        const Divider(color: Colors.white10, height: 1),
        _sheetBtn(Icons.delete_outline_rounded, kRed, 'Видалити трек',
                () { Navigator.pop(context); _deleteDialog(t); }),
        SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
      ]),
    );
  }

  Widget _sheetBtn(IconData icon, Color color, String label, VoidCallback fn) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(
          color: color == kRed ? kRed : kWhite, fontSize: 15)),
      onTap: fn,
    );
  }

  Widget _handle() => Container(
    width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
    decoration: BoxDecoration(color: kGrey.withOpacity(0.4),
        borderRadius: BorderRadius.circular(4)),
  );

  void _infoDialog(Track t) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCard,
      title: const Text('Інформація', style: TextStyle(color: kWhite)),
      content: Text(
        '🎵 ${t.title}\n🎤 ${t.artist}\n💿 ${t.album}\n⏱ ${t.durationStr}',
        style: const TextStyle(color: kGrey, height: 1.8),
      ),
      actions: [TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK', style: TextStyle(color: kOrange)),
      )],
    ));
  }

  void _deleteDialog(Track t) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCard,
      title: const Text('Видалити трек?', style: TextStyle(color: kWhite)),
      content: Text('«${t.title}» буде видалено.', style: const TextStyle(color: kGrey)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Скасувати', style: TextStyle(color: kGrey)),
        ),
        TextButton(
          onPressed: () { Navigator.pop(context); },
          child: const Text('Видалити', style: TextStyle(color: kRed)),
        ),
      ],
    ));
  }
}

// ─── TRACK TILE ───────────────────────────────────────────────────────────────

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.active,
    required this.onTap,
    required this.onMore,
    required this.onFav,
  });

  final Track       track;
  final bool        active;
  final VoidCallback onTap, onMore, onFav;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? kOrange.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: active ? Border.all(color: kOrange.withOpacity(0.3)) : null,
        ),
        child: Row(children: [
          _ArtWidget(id: track.id, size: 52),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? kOrange : kWhite,
                    fontSize: 14, fontWeight: FontWeight.w600,
                  )),
              const SizedBox(height: 3),
              Text(track.artist,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kGrey, fontSize: 12)),
            ],
          )),
          Text(track.durationStr, style: const TextStyle(color: kGrey, fontSize: 11)),
          IconButton(
            icon: Icon(track.fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: track.fav ? kOrange : kGrey.withOpacity(0.6), size: 20),
            onPressed: onFav,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded, color: kGrey, size: 20),
            onPressed: onMore,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ]),
      ),
    );
  }
}

// ─── ALBUM ART WIDGET ─────────────────────────────────────────────────────────

class _ArtWidget extends StatelessWidget {
  const _ArtWidget({required this.id, required this.size});

  final int    id;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: QueryArtworkWidget(
        id:           id,
        type:         ArtworkType.AUDIO,
        artworkWidth: size,
        artworkHeight: size,
        artworkFit:   BoxFit.cover,
        artworkBorder: BorderRadius.circular(10),
        keepOldArtwork: true,
        nullArtworkWidget: Container(
          width: size, height: size,
          color: kCard,
          child: Icon(Icons.music_note_rounded, color: kGrey, size: size * 0.45),
        ),
      ),
    );
  }
}

// ─── MINI PLAYER ─────────────────────────────────────────────────────────────

class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerState>();
    final t = p.current;
    if (t == null) return const SizedBox.shrink();

    final prog = p.dur.inMilliseconds > 0
        ? (p.pos.inMilliseconds / p.dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: kCard.withOpacity(0.92),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4),
                  blurRadius: 24)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                child: Row(children: [
                  _ArtWidget(id: t.id, size: 44),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: kWhite,
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(t.artist, maxLines: 1,
                          style: const TextStyle(color: kGrey, fontSize: 11)),
                    ],
                  )),
                  IconButton(icon: const Icon(Icons.skip_previous_rounded,
                      color: kGrey, size: 22), onPressed: p.prev),
                  IconButton(
                    icon: Icon(
                      p.playing ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_filled_rounded,
                      color: kOrange, size: 36,
                    ),
                    onPressed: p.toggle,
                  ),
                  IconButton(icon: const Icon(Icons.skip_next_rounded,
                      color: kGrey, size: 22), onPressed: p.next),
                ]),
              ),
              LinearProgressIndicator(
                value: prog,
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: const AlwaysStoppedAnimation<Color>(kOrange),
                minHeight: 2,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── PLAYER PAGE ─────────────────────────────────────────────────────────────

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});
  @override State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with TickerProviderStateMixin {

  late final AnimationController _pulse;
  late final AnimationController _ripple;
  late final Animation<double>   _pulseAnim;
  late final Animation<double>   _rippleAnim;
  bool _rippleOn = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _pulseAnim = Tween(begin: 1.0, end: 1.05).animate(
        CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _ripple = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 800));
    _rippleAnim = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _ripple, curve: Curves.easeOut));
  }

  void _doRipple() {
    setState(() => _rippleOn = true);
    _ripple.forward(from: 0).then((_) {
      if (mounted) setState(() => _rippleOn = false);
    });
  }

  @override
  void dispose() {
    _pulse.dispose(); _ripple.dispose(); super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<PlayerState>();
    final t = p.current;
    if (t == null) return const Scaffold(backgroundColor: kBg);

    if (!p.playing) _pulse.stop();
    else if (!_pulse.isAnimating) _pulse.repeat(reverse: true);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [p.accent.withOpacity(0.4), kBg, kBg],
            stops: const [0, 0.45, 1],
          ),
        ),
        child: SafeArea(child: Column(children: [
          _topBar(context, p),
          Expanded(child: _art(t, p)),
          _controls(p, t),
        ])),
      ),
    );
  }

  Widget _topBar(BuildContext context, PlayerState p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.keyboard_arrow_down_rounded,
                color: kWhite, size: 22),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        const Expanded(child: Center(
          child: Text('Зараз грає',
              style: TextStyle(fontSize: 12, color: kGrey, letterSpacing: 1)),
        )),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(Icons.timer_outlined,
                color: p.sleepOn ? kOrange : kGrey, size: 18),
          ),
          onPressed: () => _sleepSheet(p),
        ),
        GestureDetector(
          onTap: () => _speedSheet(p),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('${p.speed}×',
                style: const TextStyle(color: kWhite,
                    fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _art(Track t, PlayerState p) {
    final prog = p.dur.inMilliseconds > 0
        ? (p.pos.inMilliseconds / p.dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
      child: Stack(alignment: Alignment.center, children: [
        // Glow
        if (p.playing)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 260 * _pulseAnim.value,
              height: 260 * _pulseAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: p.accent.withOpacity(0.3),
                    blurRadius: 70, spreadRadius: 20)],
              ),
            ),
          ),

        // Ripple on play
        if (_rippleOn)
          AnimatedBuilder(
            animation: _rippleAnim,
            builder: (_, __) => Container(
              width: 240 + 160 * _rippleAnim.value,
              height: 240 + 160 * _rippleAnim.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.lightBlueAccent
                      .withOpacity((1 - _rippleAnim.value) * 0.85),
                  width: 3,
                ),
              ),
            ),
          ),

        // Art
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, child) => Transform.scale(
              scale: p.playing ? _pulseAnim.value : 1.0, child: child),
          child: Container(
            width: 260, height: 260,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 40, offset: const Offset(0, 16))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: QueryArtworkWidget(
                id:            t.id,
                type:          ArtworkType.AUDIO,
                artworkWidth:  260,
                artworkHeight: 260,
                artworkFit:    BoxFit.cover,
                artworkBorder: BorderRadius.circular(26),
                keepOldArtwork: true,
                nullArtworkWidget: Container(
                  color: kCard,
                  child: const Icon(Icons.music_note_rounded,
                      size: 80, color: kGrey),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _controls(PlayerState p, Track t) {
    final prog = p.dur.inMilliseconds > 0
        ? (p.pos.inMilliseconds / p.dur.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(children: [
        // Title + fav
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kWhite,
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(t.artist, style: const TextStyle(color: kGrey, fontSize: 14)),
            ],
          )),
          IconButton(
            icon: Icon(t.fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: t.fav ? kOrange : kGrey, size: 26),
            onPressed: () {
              context.read<LibraryState>().toggleFav(t);
              setState(() {});
            },
          ),
        ]),
        const SizedBox(height: 20),

        // Seekbar
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            activeTrackColor: kOrange,
            inactiveTrackColor: Colors.white.withOpacity(0.12),
            thumbColor: kOrange,
            overlayColor: kOrange.withOpacity(0.2),
          ),
          child: Slider(
            value: prog,
            onChanged: (v) =>
                p.seekTo(Duration(milliseconds: (v * p.dur.inMilliseconds).toInt())),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Text(_fmt(p.pos), style: const TextStyle(color: kGrey, fontSize: 11)),
            const Spacer(),
            Text(_fmt(p.dur), style: const TextStyle(color: kGrey, fontSize: 11)),
          ]),
        ),
        const SizedBox(height: 8),

        // Shuffle + Repeat
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(
            icon: Icon(Icons.shuffle_rounded,
                color: p.shuffle ? kOrange : kGrey.withOpacity(0.4), size: 24),
            onPressed: () => p.setShuffle(!p.shuffle),
          ),
          IconButton(
            icon: Icon(
              p.repeat == Repeat.one
                  ? Icons.repeat_one_rounded
                  : Icons.repeat_rounded,
              color: p.repeat == Repeat.off
                  ? kGrey.withOpacity(0.4) : kOrange,
              size: 24,
            ),
            onPressed: p.cycleRepeat,
          ),
        ]),

        // Prev / Play / Next
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
            icon: const Icon(Icons.skip_previous_rounded, color: kWhite, size: 40),
            onPressed: p.prev,
          ),
          const SizedBox(width: 24),
          GestureDetector(
            onTap: () {
              final was = p.playing;
              p.toggle();
              if (!was) _doRipple();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 72, height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle, color: kWhite,
                boxShadow: [BoxShadow(
                    color: kOrange.withOpacity(0.45),
                    blurRadius: 28, spreadRadius: 2)],
              ),
              child: Center(child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  p.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  key: ValueKey(p.playing),
                  color: kBg, size: 36,
                ),
              )),
            ),
          ),
          const SizedBox(width: 24),
          IconButton(
            icon: const Icon(Icons.skip_next_rounded, color: kWhite, size: 40),
            onPressed: p.next,
          ),
        ]),
      ]),
    );
  }

  void _sleepSheet(PlayerState p) {
    if (p.sleepOn) {
      showDialog(context: context, builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Таймер активний', style: TextStyle(color: kWhite)),
        content: Text('Залишилось: ${p.sleepStr}',
            style: const TextStyle(color: kGrey)),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); p.cancelSleep(); },
              child: const Text('Скасувати', style: TextStyle(color: kRed))),
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Закрити', style: TextStyle(color: kGrey))),
        ],
      ));
      return;
    }
    final items = {
      '5 хв': 5, '10 хв': 10, '15 хв': 15,
      '20 хв': 20, '30 хв': 30, '45 хв': 45, '60 хв': 60,
    };
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _Sheet(
        title: 'Таймер сну',
        items: items.keys.toList(),
        onTap: (i) {
          Navigator.pop(context);
          p.startSleep(Duration(minutes: items.values.toList()[i]));
        },
      ),
    );
  }

  void _speedSheet(PlayerState p) {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _Sheet(
        title: 'Швидкість',
        items: speeds.map((s) => '${s}×').toList(),
        onTap: (i) { Navigator.pop(context); p.setSpeed(speeds[i]); },
      ),
    );
  }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

// ─── SETTINGS PAGE ────────────────────────────────────────────────────────────

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final p = context.watch<PlayerState>();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        title: const Text('Налаштування',
            style: TextStyle(color: kWhite, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: kWhite),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _section('ЗОВНІШНІЙ ВИГЛЯД'),
        _card([
          _tile(Icons.photo_rounded, const Color(0xFF5AC8FA), 'Фон з галереї',
              'Обрати своє зображення',
              trailing: _pill('Обрати', kOrange, () {})),
          _div(),
          _tile(Icons.clear_rounded, kGrey, 'Скинути фон', null,
              trailing: _pill('Скинути', kCard2, () {})),
        ]),

        _section('ОСНОВНІ'),
        _card([
          _swTile(Icons.notifications_rounded, kRed, 'Сповіщення', null,
              s.notifs, (v) => s.set('notifs', v)),
          _div(),
          _swTile(Icons.back_hand_rounded, const Color(0xFF34C759),
              'Жести наближення', 'Пауза/пуск жестом',
              s.proximity, (v) => s.set('prox', v)),
          _div(),
          _swTile(Icons.download_rounded, const Color(0xFF5AC8FA),
              'Авто-завантаження обкладинок', null,
              false, (_) {}),
        ]),

        _section('ВІДТВОРЕННЯ'),
        _card([
          // Speed slider
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: kOrange,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.speed_rounded, color: kWhite, size: 18)),
              const SizedBox(width: 14),
              const Text('Швидкість', style: TextStyle(color: kWhite, fontSize: 16)),
              const Spacer(),
              Text('${p.speed}×',
                  style: const TextStyle(color: kOrange,
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3, thumbColor: kOrange,
              activeTrackColor: kOrange,
              inactiveTrackColor: Colors.white.withOpacity(0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: p.speed.clamp(0.5, 2.0), min: 0.5, max: 2.0, divisions: 6,
              onChanged: (v) => p.setSpeed((v * 4).round() / 4),
            ),
          ),
          _div(),
          _swTile(Icons.shuffle_rounded, const Color(0xFFFF9500),
              'Кросфейд', 'Плавний перехід',
              s.crossfade, (v) => s.set('cross', v)),
          _div(),
          _swTile(Icons.directions_car_rounded, const Color(0xFFFF9500),
              'Режим авто', 'Великі кнопки для водіїв',
              s.carMode, (v) => s.set('car', v)),
        ]),

        _section('ЗВУК'),
        _card([
          // Bass slider
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: kOrange,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.graphic_eq_rounded,
                      color: kWhite, size: 18)),
              const SizedBox(width: 14),
              const Text('Бас-буст', style: TextStyle(color: kWhite, fontSize: 16)),
              const Spacer(),
              Text('${s.bass}%',
                  style: const TextStyle(color: kOrange,
                      fontWeight: FontWeight.w700, fontSize: 14)),
            ]),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3, thumbColor: kOrange,
              activeTrackColor: kOrange,
              inactiveTrackColor: Colors.white.withOpacity(0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: s.bass.toDouble(), min: 0, max: 100, divisions: 20,
              onChanged: (v) => s.set('bass', v.toInt()),
            ),
          ),
          _div(),
          _navTile(Icons.equalizer_rounded, const Color(0xFF34C759),
              'Еквалайзер', 'Пресети налаштування',
                  () => _eqSheet(context, s)),
          _div(),
          _navTile(Icons.bedtime_rounded, const Color(0xFF5AC8FA),
              'Таймер сну', 'Автоматична зупинка', () {}),
        ]),

        _section('ІНФОРМАЦІЯ'),
        _card([
          _navTile(Icons.info_outline_rounded, const Color(0xFF007AFF),
              'Про застосунок', 'AURA Music v1.0',
                  () => _aboutDialog(context)),
        ]),

        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _section(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 0, 8),
    child: Text(t, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: kGrey, letterSpacing: 0.5)),
  );

  Widget _card(List<Widget> ch) => Container(
    decoration: BoxDecoration(color: kCard,
        borderRadius: BorderRadius.circular(14)),
    child: Column(children: ch),
  );

  Widget _div() => Padding(
      padding: const EdgeInsets.only(left: 62),
      child: Divider(height: 1, color: Colors.white.withOpacity(0.06)));

  Widget _tile(IconData icon, Color ic, String title, String? sub,
      {required Widget trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(color: ic,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: kWhite, size: 18)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: kWhite, fontSize: 16)),
            if (sub != null)
              Text(sub, style: const TextStyle(color: kGrey, fontSize: 12)),
          ],
        )),
        trailing,
      ]),
    );
  }

  Widget _swTile(IconData icon, Color ic, String title, String? sub,
      bool val, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(width: 32, height: 32,
            decoration: BoxDecoration(color: ic,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: kWhite, size: 18)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: kWhite, fontSize: 16)),
            if (sub != null)
              Text(sub, style: const TextStyle(color: kGrey, fontSize: 12)),
          ],
        )),
        Switch(value: val, onChanged: onChanged,
            activeColor: kOrange, inactiveTrackColor: kCard2),
      ]),
    );
  }

  Widget _navTile(IconData icon, Color ic, String title, String? sub,
      VoidCallback onTap) {
    return GestureDetector(onTap: onTap,
        child: _tile(icon, ic, title, sub,
            trailing: const Icon(Icons.chevron_right_rounded, color: kGrey, size: 18)));
  }

  Widget _pill(String label, Color color, VoidCallback fn) {
    return GestureDetector(onTap: fn,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: color,
            borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: const TextStyle(color: kWhite,
                fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  void _eqSheet(BuildContext context, AppSettings s) {
    final presets = ['Normal','Pop','Rock','Jazz','Classical','Dance','Hip-Hop'];
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _Sheet(
        title: 'Еквалайзер',
        items: presets,
        selected: s.eqPreset,
        onTap: (i) { Navigator.pop(context); s.set('eq', i); },
      ),
    );
  }

  void _aboutDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCard,
      title: const Text('AURA Music', style: TextStyle(color: kWhite)),
      content: const Text(
        'Версія 1.0\n\n'
            '👤  Засновник: Артем Процьків\n'
            '💻  Мова: Dart / Flutter\n'
            '📱  iOS + Android\n\n'
            '✊/🖐  Жест → пауза/пуск\n'
            '💧  Водні хвилі при відтворенні\n'
            '🎨  Кастомний фон з галереї\n'
            '🎚  Еквалайзер + бас-буст\n'
            '😴  Таймер сну',
        style: TextStyle(color: kGrey, height: 1.7),
      ),
      actions: [TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK', style: TextStyle(color: kOrange)),
      )],
    ));
  }
}

// ─── BOTTOM SHEET HELPER ──────────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.title,
    required this.items,
    required this.onTap,
    this.selected = -1,
  });

  final String        title;
  final List<String>  items;
  final int           selected;
  final void Function(int) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 36, height: 4,
        margin: const EdgeInsets.only(top: 12, bottom: 8),
        decoration: BoxDecoration(color: kGrey.withOpacity(0.4),
            borderRadius: BorderRadius.circular(4)),
      ),
      Text(title,
          style: const TextStyle(color: kWhite,
              fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      ...List.generate(items.length, (i) => ListTile(
        title: Text(items[i],
            style: TextStyle(
              color: selected == i ? kOrange : kWhite,
              fontWeight: selected == i ? FontWeight.w700 : FontWeight.normal,
            )),
        trailing: selected == i
            ? const Icon(Icons.check_rounded, color: kOrange) : null,
        onTap: () => onTap(i),
      )),
      SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
    ]);
  }
}