import 'package:flutter/material.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Determining Pork Freshness',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
      ),
      home: const MyHomePage(title: 'Determining Pork Freshness'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  File? _image;
  Interpreter? _porkInterpreter;
  Interpreter? _freshInterpreter;
  String? _result;

  @override
  void initState() {
    super.initState();
    _loadModels();
  }

  Future<void> _loadModels() async {
    _porkInterpreter = await Interpreter.fromAsset('assets/pork.tflite');
    _freshInterpreter = await Interpreter.fromAsset('assets/fresh.tflite');
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
      await _runModel(_image!);
    }
  }

  Future<void> _captureImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() => _image = File(pickedFile.path));
      await _runModel(_image!);
    }
  }

  Future<void> _runModel(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return;

    final resized = img.copyResize(image, width: 224, height: 224);

    // Step 1: ตรวจว่าเป็นหมูหรือไม่
    final rgbInput = _convertToRGBInput(resized);
    final porkOutput = List.filled(2, 0.0).reshape([1, 2]);
    _porkInterpreter?.run(rgbInput, porkOutput);

    final porkProb = porkOutput[0][1]; // index 1 = Pork
    if (porkProb < 0.7) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('แจ้งเตือน'),
            content: const Text('ภาพนี้ไม่ใช่เนื้อหมูสามชั้น กรุณาลองใหม่อีกครั้ง'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  setState(() {
                    _result = null;
                    _image = null;
                  });
                },
                child: const Text('ตกลง'),
              ),
            ],
          );
        },
      );
      return;
    }

    // Step 2: วิเคราะห์ความสด
    final hsvInput = _convertToHSVInput(resized);
    final freshOutput = List.filled(3, 0.0).reshape([1, 3]);
    _freshInterpreter?.run(hsvInput, freshOutput);

    setState(() {
      final labels = ['Fresh', 'Half-Fresh', 'Spoiled'];
      final List<double> probs = List<double>.from(freshOutput[0]);
      final maxProb = probs.reduce((a, b) => a > b ? a : b);
      final index = probs.indexOf(maxProb);
      _result = 'ระดับความสด: ${labels[index]}';
    });
  }

  Color _getResultColor(String? result) {
    if (result == null) return Colors.black;

    if (result.contains('Half-Fresh')) return Colors.deepOrangeAccent; // กึ่งสด
    if (result.contains('Fresh')) return Colors.green;       // สด
    if (result.contains('Spoiled')) return Colors.red;       // เสีย

    return Colors.black; // default
  }

  List<List<List<List<double>>>> _convertToRGBInput(img.Image image) {
    return [
      List.generate(224, (y) =>
          List.generate(224, (x) {
            final pixel = image.getPixel(x, y);
            final r = pixel.r / 255.0;
            final g = pixel.g / 255.0;
            final b = pixel.b / 255.0;
            return [r, g, b];
          })
      )
    ];
  }

  List<List<List<List<double>>>> _convertToHSVInput(img.Image image) {
    return [
      List.generate(224, (y) =>
          List.generate(224, (x) {
            final pixel = image.getPixel(x, y);
            final r = pixel.r / 255.0;
            final g = pixel.g / 255.0;
            final b = pixel.b / 255.0;
            final hsv = _rgbToHsv(r, g, b);
            return [hsv[0] / 255.0, hsv[1] / 255.0, hsv[2] / 255.0];
          })
      )
    ];
  }

  List<double> _rgbToHsv(double r, double g, double b) {
    final max = [r, g, b].reduce((a, b) => a > b ? a : b);
    final min = [r, g, b].reduce((a, b) => a < b ? a : b);
    final diff = max - min;
    double h = 0;

    if (diff != 0) {
      if (max == r) h = (60 * ((g - b) / diff) + 360) % 360;
      else if (max == g) h = (60 * ((b - r) / diff) + 120) % 360;
      else if (max == b) h = (60 * ((r - g) / diff) + 240) % 360;
    }

    final s = max == 0 ? 0.0 : (diff / max);
    final v = max;

    return [h * 255 / 360, s * 255, v * 255];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Determining Pork Freshness',
          style: TextStyle(
            fontSize: 24,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF3853FF), // สีฝั่งซ้าย
                Color(0xFF04D8CD), // สีฝั่งขวา
              ],
              begin: Alignment.topLeft,// เริ่มต้น บนซ้าย
              end: Alignment.bottomRight, // สิ่นสุดที่ ล่างขวา
            ),
          ),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: <Widget>[
              Card(
                margin: const EdgeInsets.all(10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12), // เพิ่มมุมโค้งเหมือนปุ่ม
                ),
                child: Container(
                  width: MediaQuery.of(context).size.width / 1.2,
                  height: MediaQuery.of(context).size.height / 2.7,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF3853FF), // โทนสีฝั่งซ้าย
                        Color(0xFF04D8CD), // โทนสีฝั่งขวา
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: _image == null
                      ? const Icon(
                    Icons.image_outlined,
                    size: 125,
                    color: Colors.white,
                  )
                      : ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _image!,
                    ),
                  ),
                ),
              ),

              Card(
                color: Colors.transparent,
                elevation: 0,
                margin: const EdgeInsets.all(20),
                child: Container(
                  padding: const EdgeInsets.all(15),
                  width: MediaQuery.of(context).size.width,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: _image == null
                        ? const [
                      Text(
                        'กรุณาเลือก Function สำหรับการประเมินเนื้อหมูสามชั้น',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ]
                        : [
                      const Text(
                        'ระดับความสดของเนื้อหมูชิ้นนี้',
                        style: TextStyle(
                          fontSize: 24,
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _result ?? '',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          color: _getResultColor(_result),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ปุ่มแยกกัน 2 อัน
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  children: [
                    // ปุ่มเลือกรูปภาพ
                    Expanded(
                      child: InkWell(
                        onTap: _pickImage,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF3853FF), // โทนสีฝั่งซ้าย
                                Color(0xFF04D8CD), // โทนสีฝั่งขวา
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.image, color: Colors.white, size: 60),
                              SizedBox(height: 8),
                              Text(
                                "เลือกรูปภาพ",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ปุ่มถ่ายรูป
                    Expanded(
                      child: InkWell(
                        onTap: _captureImage,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 25),
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF3853FF), // โทนสีฝั่งซ้าย
                                Color(0xFF04D8CD), // โทนสีฝั่งขวา
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.camera_alt, color: Colors.white, size: 60),
                              SizedBox(height: 8),
                              Text(
                                "ถ่ายรูป",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
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
    );
  }
}
