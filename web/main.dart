import 'dart:html';
import 'dart:async';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';
import 'dart:web_gl';
import 'dart:math';
import 'dart:js';

class PhotosphereViewer {
  static const String VERTEX_SHADER_SOURCE = """
      attribute vec3 a_vertex;
      attribute vec2 a_uv;

      uniform mat4 u_mvpmatrix;

      varying vec2 v_uv;

      void main(void) {
          gl_Position = u_mvpmatrix * vec4(a_vertex, 1.0);
          v_uv = a_uv;
      }
    """;

  static const String FRAGMENT_SHADER_SOURCE = """
      precision highp float;

      varying vec2 v_uv;

      uniform sampler2D u_photosphere;

      void main(void) {
          gl_FragColor = texture2D(u_photosphere, v_uv);
      }
    """;

  RenderingContext gl;
  Program program;
  CanvasElement canvas;

  bool mouseDown = false;
  int lastMouseX = null;
  int lastMouseY = null;
  int totX = 0;
  int totY = 0;

  UniformLocation mvpMatrixUniform, samplerUniform;
  int vertexPositionAttribute, textureCoordAttribute;

  Matrix4 mvpMatrix;

  Texture sphereTexture;

  Buffer sphereBuffer;
  int numIndices;

  var keys = <int, bool>{
  };

  void rebuildRotationMatrix() {
    var sphereRotationMatrix = new Matrix4
    .identity()
      ..rotate(new Vector3(1.0, 0.0, 0.0), radians(totY / 5 + 90))
      ..rotate(new Vector3(0.0, 0.0, 1.0), radians(-totX / 5));

    mvpMatrix = makePerspectiveMatrix(
        radians(45.0), canvas.width / canvas.height, 0.1, 10000.0).multiply(
        new Matrix4.identity()
        .translate(new Vector3(0.0, 0.0, 0.0))
        .multiply(sphereRotationMatrix));
  }

  void updateViewport() {
    canvas
      ..width = window.innerWidth
      ..height = window.innerHeight;
  }

  PhotosphereViewer() {
    canvas = document.querySelector('#photosphere-canvas');
    updateViewport();
    gl = canvas.getContext("experimental-webgl");

    rebuildRotationMatrix();

    for (var key in [["left", 37], ["right", 39], ["up", 38], ["down", 40]]) {
      var id = key[0];
      var code = key[1];
      var e = document.querySelector("#$id");
      e.onMouseDown.listen((Event) => keys[code] = true);
      e.onMouseUp.listen((Event) => keys[code] = false);
      e.onMouseLeave.listen((Event) => keys[code] = false);
    }

    canvas.onMouseDown.listen((MouseEvent event) {
      mouseDown = true;
      lastMouseX = event.client.x;
      lastMouseY = event.client.y;
    });
    window.onResize.listen((Event) {
      updateViewport();
      rebuildRotationMatrix();
    });
    document.onKeyDown.listen((KeyboardEvent event) => keys[event.keyCode] = true);
    document.onKeyUp.listen((KeyboardEvent event) => keys[event.keyCode] = false);
    document.onBlur.listen((Event) => keys.clear());
    document.onMouseUp.listen((MouseEvent event) => mouseDown = false);

    document.onFullscreenChange.listen((Event e) {
//      var element = document.querySelector("#fullscreen-button");
//      bool fullscreen = element.style.display == 'none';
//      element.style.display = fullscreen ? 'block' : 'none';
    });

    document.querySelector("#fullscreen-button-on").onClick.listen((Event e) {
      fullscreenWorkaround(document.querySelector("#container"));
      updateViewport();
      rebuildRotationMatrix();
    });

    document.querySelector("#fullscreen-button-off").onClick.listen((Event e) {
      fullscreenWorkaroundOff();
      updateViewport();
      rebuildRotationMatrix();
    });

    document.onMouseMove.listen((MouseEvent event) {
      if (!mouseDown) {
        return;
      }

      var curX = event.client.x;
      var curY = event.client.y;

      totX += curX - lastMouseX;
      totY += curY - lastMouseY;

      lastMouseX = curX;
      lastMouseY = curY;

      rebuildRotationMatrix();
    }

    );
  }

  bool init() {
    if (gl == null) {
      return false;
    }

    var vs = gl.createShader(RenderingContext.VERTEX_SHADER);
    gl.shaderSource(vs, VERTEX_SHADER_SOURCE);
    gl.compileShader(vs);

    var fs = gl.createShader(RenderingContext.FRAGMENT_SHADER);
    gl.shaderSource(fs, FRAGMENT_SHADER_SOURCE);
    gl.compileShader(fs);

    var p = gl.createProgram();
    gl.attachShader(p, vs);
    gl.attachShader(p, fs);
    gl.linkProgram(p);
    gl.useProgram(p);

    if (!gl.getShaderParameter(vs, RenderingContext.COMPILE_STATUS)) {
      print(gl.getShaderInfoLog(vs));
    }

    if (!gl.getShaderParameter(fs, RenderingContext.COMPILE_STATUS)) {
      print(gl.getShaderInfoLog(fs));
    }

    if (!gl.getProgramParameter(p, RenderingContext.LINK_STATUS)) {
      print(gl.getProgramInfoLog(p));
    }

    program = p;

    vertexPositionAttribute = gl.getAttribLocation(program, "a_vertex");
    textureCoordAttribute = gl.getAttribLocation(program, "a_uv");
    mvpMatrixUniform = gl.getUniformLocation(program, "u_mvpmatrix");
    samplerUniform = gl.getUniformLocation(program, "u_photosphere");

    gl.enableVertexAttribArray(vertexPositionAttribute);
    gl.enableVertexAttribArray(textureCoordAttribute);

    var radius = 500;
    var divide = 30;

    var interleaved = [];

    var pi = PI;
    var tau = PI * 2;
    var tau_div = tau / divide;
    var pi_div = pi / divide;
    for (int i = 0; i < divide; ++i) {
      var phi1 = i * tau_div,
      phi2 = (i + 1) * tau_div;
      for (int j = 0; j <= divide; ++j) {
        var theta = j * pi_div;
        var s = phi2 / tau,
        t = theta / pi;
        var dx = sin(theta) * cos(phi2);
        var dy = sin(theta) * sin(phi2);
        var dz = cos(theta);
        interleaved
          ..add(radius * dx)
          ..add(radius * dy)
          ..add(radius * dz)
          ..add(s)
          ..add(t);
        s = phi1 / tau;
        dx = sin(theta) * cos(phi1);
        dy = sin(theta) * sin(phi1);
        interleaved
          ..add(radius * dx)
          ..add(radius * dy)
          ..add(radius * dz)
          ..add(s)
          ..add(t);
      }
    }

    numIndices = (interleaved.length / 5).round();

    sphereBuffer = gl.createBuffer();
    gl.bindBuffer(ARRAY_BUFFER, sphereBuffer);
    gl.bufferDataTyped(ARRAY_BUFFER, new Float32List.fromList(interleaved), STATIC_DRAW);

    sphereTexture = gl.createTexture();
    var element = new ImageElement();
    element.onLoad.listen((e) {
      gl.pixelStorei(UNPACK_FLIP_Y_WEBGL, 1);

      gl.bindTexture(TEXTURE_2D, sphereTexture);
      gl.texImage2DImage(TEXTURE_2D, 0, RGBA, RGBA, UNSIGNED_BYTE, element);
      gl.texParameteri(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
      gl.texParameteri(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR);

      gl.bindTexture(TEXTURE_2D, null);

      // Wait for image to finish loading before getting rid of the spinner
      //
      //
      document.querySelector("#fullscreen-button-on").style.display = 'block';
      document.querySelector("#photosphere-load").style.display = "none";
      document.querySelector("#photosphere-canvas").style.display = "block";

      poll();
      run();
    });
    element.src = Uri.base.queryParameters['i'];
    return true;
  }

  void update() {
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clear(COLOR_BUFFER_BIT | DEPTH_BUFFER_BIT);

    gl.activeTexture(TEXTURE0);
    gl.bindTexture(TEXTURE_2D, sphereTexture);
    gl.uniform1i(samplerUniform, 0);
    gl.uniformMatrix4fv(mvpMatrixUniform, false, mvpMatrix.storage);

    gl.bindBuffer(ARRAY_BUFFER, sphereBuffer);
    // Stride is 20: 12 vertices + 8 uvs
    gl.vertexAttribPointer(vertexPositionAttribute, 3, FLOAT, false, 20, 0);
    gl.vertexAttribPointer(textureCoordAttribute, 2, FLOAT, false, 20, 12);
    gl.drawArrays(TRIANGLE_STRIP, 0, numIndices);
  }


  void poll() {
    new Timer.periodic(new Duration(milliseconds: (1000 / 120).round()), (Timer timer) {
      num dx = 0;
      num dy = 0;
      if (keys[37]) dx -= 1;
      if (keys[39]) dx += 1;
      if (keys[38]) dy -= 1;
      if (keys[40]) dy += 1;

      totX += min(1, max(-1, dx));
      totY += min(1, max(-1, dy));
      rebuildRotationMatrix();
    });
  }

  void run() async {
    while (true) {
      var time = await window.animationFrame;
      update();
    }
  }
}

void fullscreenWorkaround(Element element) {
  var elem = new JsObject.fromBrowserObject(element);
  List<String> vendors = ['requestFullscreen', 'mozRequestFullScreen', 'webkitRequestFullscreen', 'msRequestFullscreen'];
  for (String vendor in vendors) {
    if (elem.hasProperty(vendor)) {
      elem.callMethod(vendor);
      return;
    }
  }
}

void fullscreenWorkaroundOff() {
  var elem = new JsObject.fromBrowserObject(document);
  List<String> vendors = ['exitFullscreen, ''mozCancelFullScreen', 'mozCancelFullScreen', 'webkitCancelFullScreen', 'msExitFullscreen'];
  for (String vendor in vendors) {
    if (elem.hasProperty(vendor)) {
      elem.callMethod(vendor);
      return;
    }
  }
}

var app;

void main() {
  app = new PhotosphereViewer();
  if (app.init()) {
    print('OK!');
  } else {
    document.querySelector("#container").style.display = "none";
    document.querySelector('#error').appendHtml(
        """<p>Sorry, your browser probably doesn\'t support <a href="http://get.webgl.org/" target="_blank">WebGL</a>.</p>""");
  }
}
