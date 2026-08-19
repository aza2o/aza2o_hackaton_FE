package com.shift.shift_app

import io.flutter.embedding.android.FlutterFragmentActivity

// health 패키지가 Health Connect 권한 요청에 registerForActivityResult를 쓰기 때문에
// FlutterActivity가 아닌 FlutterFragmentActivity가 필요하다 (health README §Android 14).
class MainActivity : FlutterFragmentActivity()
