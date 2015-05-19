import 'dart:html';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';
import 'dart:web_gl';
import 'dart:math';

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
          vec4 textureColor = texture2D(u_photosphere, vec2(v_uv.s, v_uv.t));
          gl_FragColor = textureColor;
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

  void rebuildRotationMatrix() {
    var sphereRotationMatrix = new Matrix4
    .identity()
      ..rotate(new Vector3(1.0, 0.0, 0.0), radians(totY / 5 + 90))
      ..rotate(new Vector3(0.0, 0.0, 1.0), radians(-totX / 5));

    mvpMatrix = makePerspectiveMatrix(
        radians(60.0), canvas.width / canvas.height, 0.1, 10000.0).multiply(
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

    canvas.onMouseDown.listen((MouseEvent event) {
      mouseDown = true;
      lastMouseX = event.client.x;
      lastMouseY = event.client.y;
    });
    window.onResize.listen((Event) {
      updateViewport();
      rebuildRotationMatrix();
    });
    document.onKeyDown.listen((KeyboardEvent event) {
      var d = 3;
      switch (event.keyCode) {
        case 37:
          totX -= d;
          break;
        case 39:
          totX += d;
          break;
        case 38:
          totY -= d;
          break;
        case 40:
          totY += d;
          break;
      }
      rebuildRotationMatrix();
    });
    document.onMouseUp.listen((MouseEvent event) {
      mouseDown = false;
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
    });
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
    gl.enableVertexAttribArray(vertexPositionAttribute);
    textureCoordAttribute = gl.getAttribLocation(program, "a_uv");
    gl.enableVertexAttribArray(textureCoordAttribute);
    mvpMatrixUniform = gl.getUniformLocation(program, "u_mvpmatrix");
    samplerUniform = gl.getUniformLocation(program, "u_photosphere");

    //"http://cors-xysoft.rhcloud.com/cors?p=" +
    loadTexture(Uri.base.queryParameters['i'], (Texture text, ImageElement ele) {
      gl.pixelStorei(UNPACK_FLIP_Y_WEBGL, 1);

      gl.bindTexture(TEXTURE_2D, text);
      gl.texImage2DImage(TEXTURE_2D, 0, RGBA, RGBA, UNSIGNED_BYTE, ele);
      gl.texParameteri(TEXTURE_2D, TEXTURE_MAG_FILTER, LINEAR);
      gl.texParameteri(TEXTURE_2D, TEXTURE_MIN_FILTER, LINEAR_MIPMAP_NEAREST);
      gl.generateMipmap(TEXTURE_2D);

      gl.bindTexture(TEXTURE_2D, null);

      sphereTexture = text;
    });

    var radius = 50;
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

    return true;
  }

  void loadTexture(String url, handle(Texture tex, ImageElement ele)) {
    var texture = gl.createTexture();
    var element = new ImageElement();
    element.onLoad.listen((e) => handle(texture, element));
    element.src = url;
  }

  void update() {
    gl.viewport(0, 0, canvas.width, canvas.height);
    gl.clear(COLOR_BUFFER_BIT | DEPTH_BUFFER_BIT);

    gl.activeTexture(TEXTURE0);
    gl.bindTexture(TEXTURE_2D, sphereTexture);
    gl.uniform1i(samplerUniform, 0);

    gl.bindBuffer(ARRAY_BUFFER, sphereBuffer);
    // Stride is 20: 12 vertices + 8 uvs
    gl.vertexAttribPointer(vertexPositionAttribute, 3, FLOAT, false, 20, 0);
    gl.vertexAttribPointer(textureCoordAttribute, 2, FLOAT, false, 20, 12);

    gl.uniformMatrix4fv(mvpMatrixUniform, false, mvpMatrix.storage);

    gl.drawArrays(TRIANGLE_STRIP, 0, numIndices);

    window.requestAnimationFrame((num time) => update());
  }

  void run() {
    window.requestAnimationFrame((num time) => update());
  }
}

void main() {
  var app = new PhotosphereViewer();
  if (app.init()) {
    app.run();
  } else {
    document.querySelector('body').appendHtml(
        """<p>Sorry, your browser probably doesn\'t support WebGL.
      For more information visit
      <a href="http://get.webgl.org/" target="_blank">http://get.webgl.org/</a>.</p>""");
  }
}
