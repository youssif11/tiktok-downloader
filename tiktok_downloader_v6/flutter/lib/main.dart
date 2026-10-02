import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String defaultBackend = 'http://10.0.2.2:8000';

void main() => runApp(const DownloaderApp());

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF67103), brightness: Brightness.dark),
      scaffoldBackgroundColor: const Color(0xFF101315),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    ),
    home: const HomePage(),
  );
}

class MediaItem {
  final String url;
  final String type;
  final String label;
  final String ext;
  final double? sizeMb;
  final bool watermark;
  MediaItem({required this.url, required this.type, required this.label, required this.ext, this.sizeMb, this.watermark = false});
  factory MediaItem.fromJson(Map<String,dynamic> j) => MediaItem(
    url: '${j['url'] ?? ''}', type: '${j['type'] ?? 'video'}',
    label: '${j['label'] ?? j['format'] ?? j['ext'] ?? 'Media'}', ext: '${j['ext'] ?? 'mp4'}',
    sizeMb: (j['size_mb'] as num?)?.toDouble(), watermark: j['watermark'] == true,
  );
}

class QueueItem {
  final String source;
  String title = 'جاهز للتنزيل';
  String platform = '';
  String? thumb;
  List<MediaItem> media = [];
  int selected = 0;
  double progress = 0;
  double speed = 0;
  String status = 'انتظار';
  CancelToken cancel = CancelToken();
  QueueItem(this.source);
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState()=>_HomePageState(); }
class _HomePageState extends State<HomePage> {
  final controller = TextEditingController();
  final dio = Dio();
  final List<QueueItem> queue = [];
  String backend = defaultBackend;
  bool busy = false;

  @override void initState(){ super.initState(); _loadBackend(); }
  Future<void> _loadBackend() async { final p=await SharedPreferences.getInstance(); setState(()=>backend=p.getString('backend') ?? defaultBackend); }
  Future<void> _settings() async {
    final c=TextEditingController(text: backend);
    final value=await showDialog<String>(context:context,builder:(_)=>AlertDialog(title:const Text('إعدادات'),content:TextField(controller:c,decoration:const InputDecoration(labelText:'عنوان Backend')),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('إلغاء')),FilledButton(onPressed:()=>Navigator.pop(context,c.text.trim()),child:const Text('حفظ'))]));
    if(value!=null && value.isNotEmpty){ final p=await SharedPreferences.getInstance(); await p.setString('backend',value); setState(()=>backend=value); }
  }
  void paste(){ controller.text = ''; }
  Future<void> resolveAll() async {
    final links=controller.text.split(RegExp(r'[\n,\s]+')).map((e)=>e.trim()).where((e)=>e.startsWith('http')).toSet();
    if(links.isEmpty){_msg('ضع رابطًا واحدًا على الأقل');return;}
    setState((){ for(final l in links){ queue.add(QueueItem(l)); } busy=true; });
    for(final item in queue.where((q)=>q.status=='انتظار')) { await _resolve(item); }
    setState(()=>busy=false);
  }
  Future<void> _resolve(QueueItem item) async {
    setState(()=>item.status='تحليل...');
    try{
      final r=await dio.get('$backend/api/resolve',queryParameters:{'url':item.source});
      final d=Map<String,dynamic>.from(r.data);
      if(d['success']!=true) throw Exception(d['error']?['message'] ?? 'فشل التحليل');
      final medias=((d['formats'] as List?) ?? (d['medias'] as List?) ?? []).whereType<Map>().map((x)=>MediaItem.fromJson(Map<String,dynamic>.from(x))).where((m)=>m.url.isNotEmpty).toList();
      setState((){ item.media=medias; item.platform='${d['platform'] ?? ''}'; item.title='${d['meta']?['title'] ?? d['meta']?['caption'] ?? d['platform'] ?? 'Video'}'; item.thumb=d['meta']?['thumbnail']?.toString(); item.status=medias.isEmpty?'لا توجد وسائط':'جاهز'; });
    }catch(e){setState(()=>item.status='خطأ: $e');}
  }
  Future<void> downloadItem(QueueItem item) async {
    if(item.media.isEmpty){_msg('حلّل الرابط أولًا');return;}
    final m=item.media[item.selected.clamp(0,item.media.length-1)];
    setState(()=>item.status='تنزيل...');
    final dir=await getTemporaryDirectory();
    final safe=item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').substring(0,item.title.length.clamp(0,80));
    final path='${dir.path}/${safe.isEmpty?'video':safe}.${m.ext == 'jpeg' ? 'jpg' : m.ext}';
    try{
      final sw=Stopwatch()..start(); double last=0; int lastMs=0;
      await dio.download(m.url,path,cancelToken:item.cancel,onReceiveProgress:(received,total){
        final now=sw.elapsedMilliseconds; if(now-lastMs>250){ final sp=(received-last)/(now-lastMs)*1000; setState(()=>{item.progress=total>0?received/total:0; item.speed=sp;}); last=received; lastMs=now; }
      });
      if(m.type=='video' && (m.ext=='mp4'||m.ext=='mov'||m.ext=='m4v')) { await Gal.putVideo(path, album:'Social Downloader'); } else { await Gal.putImage(path, album:'Social Downloader'); }
      setState(()=>item.status='اكتمل');
      _msg('تم حفظ الملف في المعرض');
    } on DioException catch(e){ setState(()=>item.status=e.type==DioExceptionType.cancel?'ملغى':'فشل التنزيل'); }
    catch(e){setState(()=>item.status='فشل: $e');}
  }
  void cancel(QueueItem item){ item.cancel.cancel('user'); setState(()=>item.status='ملغى'); }
  void _msg(String s)=>ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(s)));
  String fmtSpeed(double b){ if(b<1024)return '${b.toStringAsFixed(0)} B/s'; if(b<1048576)return '${(b/1024).toStringAsFixed(1)} KB/s'; return '${(b/1048576).toStringAsFixed(1)} MB/s'; }
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Social Downloader V6'),actions:[IconButton(onPressed:_settings,icon:const Icon(Icons.settings))]),body:Padding(padding:const EdgeInsets.all(16),child:Column(children:[
    TextField(controller:controller,maxLines:5,decoration:const InputDecoration(hintText:'الصق روابط TikTok / YouTube / Instagram / Facebook وغيرها',prefixIcon:Icon(Icons.link))),
    const SizedBox(height:10), Row(children:[Expanded(child:FilledButton.icon(onPressed:busy?null:resolveAll,icon:const Icon(Icons.search),label:const Text('تحليل الروابط'))),const SizedBox(width:8),IconButton(onPressed:()=>controller.clear(),icon:const Icon(Icons.clear))]),
    const SizedBox(height:10), Expanded(child:queue.isEmpty?const Center(child:Text('لا توجد تنزيلات بعد')):ListView.builder(itemCount:queue.length,itemBuilder:(_,i)=>_card(queue[i]))),
  ])));
  Widget _card(QueueItem q)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(q.title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold))),Text(q.platform)]),const SizedBox(height:6),Text(q.status),if(q.media.isNotEmpty)DropdownButton<int>(value:q.selected.clamp(0,q.media.length-1),isExpanded:true,items:[for(int i=0;i<q.media.length;i++)DropdownMenuItem(value:i,child:Text('${q.media[i].label}  ${q.media[i].sizeMb==null?'':'(${q.media[i].sizeMb!.toStringAsFixed(1)} MB)'}'))],onChanged:(v)=>setState(()=>q.selected=v??0)),if(q.status=='تنزيل...'||q.progress>0)LinearProgressIndicator(value:q.progress),if(q.status=='تنزيل...')Padding(padding:const EdgeInsets.only(top:5),child:Text('${(q.progress*100).toStringAsFixed(0)}%  ${fmtSpeed(q.speed)}')),Row(mainAxisAlignment:MainAxisAlignment.end,children:[if(q.status=='تحليل...'||q.status=='تنزيل...')IconButton(onPressed:()=>cancel(q),icon:const Icon(Icons.cancel)),if(q.media.isNotEmpty&&q.status!='تنزيل...')FilledButton.icon(onPressed:()=>downloadItem(q),icon:const Icon(Icons.download),label:const Text('تنزيل'))])])));
}
