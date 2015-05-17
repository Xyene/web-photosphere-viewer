import 'dart:html';
import 'dart:typed_data';
import 'package:vector_math/vector_math.dart';
import 'dart:web_gl' as webgl;
import 'dart:math';
import 'dart:async';

class PhotosphereViewer {
  webgl.RenderingContext gl;
  webgl.Program program;
  CanvasElement canvas;
  bool running = false;

  var mouseDown = false;
  var lastMouseX = null;
  var lastMouseY = null;
  var totX = 0, totY = 0;

  webgl.UniformLocation pMatrixUniform, mvMatrixUniform, samplerUniform;
  int vertexPositionAttribute, textureCoordAttribute;

  Matrix4 pMatrix, mvMatrix;
  Matrix4 sphereRotationMatrix = new Matrix4.identity();

  webgl.Buffer sphereVertexPositionBuffer;
  webgl.Buffer sphereVertexTextureCoordBuffer;
  webgl.Buffer sphereVertexIndexBuffer;

  webgl.Texture sphereTexture;

  var numIndices;

  PhotosphereViewer() {
    this.canvas = document.query('#drawHere');
    this.gl = this.canvas.getContext("experimental-webgl");

    canvas.onMouseDown.listen((MouseEvent event) {
      mouseDown = true;
      lastMouseX = event.client.x;
      lastMouseY = event.client.y;
    });
    document.onMouseUp.listen((MouseEvent event) {
      mouseDown = false;
    });
    document.onMouseMove.listen((MouseEvent event) {
      if (!mouseDown) {
        return;
      }

      var newX = event.client.x;
      var newY = event.client.y;

      totX += newX - lastMouseX;
      totY += newY - lastMouseY;

      sphereRotationMatrix = new Matrix4.identity();
      sphereRotationMatrix = sphereRotationMatrix.rotate(new Vector3(1.0, 0.0, 0.0), radians(totY / 5));
      sphereRotationMatrix = sphereRotationMatrix.rotate(new Vector3(0.0, 1.0, 0.0), radians(totX / 5));

      lastMouseX = newX;
      lastMouseY = newY;
    });
  }

  bool init() {
    if (this.gl == null) {
      return false;
    }

    String vertexShaderSource = """
      attribute vec3 a_vertex;
      attribute vec2 a_uv;
  
      uniform mat4 u_mvmatrix;
      uniform mat4 u_pmatrix;
  
      varying vec2 v_uv;
  
      void main(void) {
          gl_Position = u_pmatrix * u_mvmatrix * vec4(a_vertex, 1.0);
          v_uv = a_uv;
      }
    """;

    String fragmentShaderSource = """
      precision highp float;
  
      varying vec2 v_uv;
  
      uniform sampler2D u_photosphere;
  
      void main(void) {
          vec4 textureColor = texture2D(u_photosphere, vec2(v_uv.s, v_uv.t));
          gl_FragColor = textureColor;
      }
    """;

    webgl.Shader vs = this.gl.createShader(webgl.RenderingContext.VERTEX_SHADER);
    this.gl.shaderSource(vs, vertexShaderSource);
    this.gl.compileShader(vs);

    webgl.Shader fs = this.gl.createShader(webgl.RenderingContext.FRAGMENT_SHADER);
    this.gl.shaderSource(fs, fragmentShaderSource);
    this.gl.compileShader(fs);

    webgl.Program p = this.gl.createProgram();
    this.gl.attachShader(p, vs);
    this.gl.attachShader(p, fs);
    this.gl.linkProgram(p);
    this.gl.useProgram(p);

    if (!this.gl.getShaderParameter(vs, webgl.RenderingContext.COMPILE_STATUS)) {
      print(this.gl.getShaderInfoLog(vs));
    }

    if (!this.gl.getShaderParameter(fs, webgl.RenderingContext.COMPILE_STATUS)) {
      print(this.gl.getShaderInfoLog(fs));
    }

    if (!this.gl.getProgramParameter(p, webgl.RenderingContext.LINK_STATUS)) {
      print(this.gl.getProgramInfoLog(p));
    }

    this.program = p;

    vertexPositionAttribute = gl.getAttribLocation(program, "a_vertex");
    gl.enableVertexAttribArray(vertexPositionAttribute);
    textureCoordAttribute = gl.getAttribLocation(program, "a_uv");
    gl.enableVertexAttribArray(textureCoordAttribute);
    pMatrixUniform = gl.getUniformLocation(program, "u_pmatrix");
    mvMatrixUniform = gl.getUniformLocation(program, "u_mvmatrix");
    samplerUniform = gl.getUniformLocation(program, "u_photosphere");

    loadTexture(Uri.base.queryParameters['i'], (webgl.Texture text, ImageElement ele) {
      gl.pixelStorei(webgl.UNPACK_FLIP_Y_WEBGL, 1);

      gl.bindTexture(webgl.TEXTURE_2D, text);
      gl.texImage2DImage(webgl.TEXTURE_2D, 0, webgl.RGBA, webgl.RGBA, webgl.UNSIGNED_BYTE, ele);
      gl.texParameteri(webgl.TEXTURE_2D, webgl.TEXTURE_MAG_FILTER, webgl.LINEAR);
      gl.texParameteri(webgl.TEXTURE_2D, webgl.TEXTURE_MIN_FILTER, webgl.LINEAR_MIPMAP_NEAREST);
      gl.generateMipmap(webgl.TEXTURE_2D);

      gl.bindTexture(webgl.TEXTURE_2D, null);

      sphereTexture = text;
    });

    initBuffers();
    return true;
  }
  
  Future<webgl.Texture> loadTexture(String url, handle(webgl.Texture tex, ImageElement ele)) {
    var completer = new Completer<webgl.Texture>();
    var texture = gl.createTexture();
    var element = new ImageElement();
    element.onLoad.listen((e) {
      handle(texture, element);
      completer.complete(texture);
    });
    element.src = url;
    return completer.future;
  }

  void initBuffers() {
    var latitudeBands = 30;
    var longitudeBands = 30;
    var radius = 50;

    var vertexPositionData = [];
    var textureCoordData = [];
    for (var latNumber = 0; latNumber <= latitudeBands; latNumber++) {
      var theta = latNumber * PI / latitudeBands;
      var sinTheta = sin(theta);
      var cosTheta = cos(theta);

      for (var longNumber = 0; longNumber <= longitudeBands; longNumber++) {
        var phi = longNumber * 2 * PI / longitudeBands;
        var sinPhi = sin(phi);
        var cosPhi = cos(phi);

        var nx = cosPhi * sinTheta;
        var ny = cosTheta;
        var nz = sinPhi * sinTheta;
        var u = 1 - (longNumber / longitudeBands);
        var v = 1 - (latNumber / latitudeBands);

        textureCoordData.add(u);
        textureCoordData.add(v);
        vertexPositionData.add(radius * nx);
        vertexPositionData.add(radius * ny);
        vertexPositionData.add(radius * nz);
      }
    }

    var indexData = [];
    for (var latNumber = 0; latNumber < latitudeBands; latNumber++) {
      for (var longNumber = 0; longNumber < longitudeBands; longNumber++) {
        var first = (latNumber * (longitudeBands + 1)) + longNumber;
        var second = first + longitudeBands + 1;
        indexData.add(first);
        indexData.add(second);
        indexData.add(first + 1);

        indexData.add(second);
        indexData.add(second + 1);
        indexData.add(first + 1);
      }
    }

    sphereVertexTextureCoordBuffer = gl.createBuffer();
    gl.bindBuffer(webgl.ARRAY_BUFFER, sphereVertexTextureCoordBuffer);
    gl.bufferDataTyped(webgl.ARRAY_BUFFER, new Float32List.fromList(textureCoordData), webgl.STATIC_DRAW);

    sphereVertexPositionBuffer = gl.createBuffer();
    gl.bindBuffer(webgl.ARRAY_BUFFER, sphereVertexPositionBuffer);
    gl.bufferDataTyped(webgl.ARRAY_BUFFER, new Float32List.fromList(vertexPositionData), webgl.STATIC_DRAW);

    sphereVertexIndexBuffer = gl.createBuffer();
    gl.bindBuffer(webgl.ELEMENT_ARRAY_BUFFER, sphereVertexIndexBuffer);
    gl.bufferDataTyped(webgl.ELEMENT_ARRAY_BUFFER, new Uint16List.fromList(indexData), webgl.STATIC_DRAW);
    numIndices = indexData.length;
  }

  void update() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;

    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.clear(webgl.COLOR_BUFFER_BIT | webgl.DEPTH_BUFFER_BIT);

    pMatrix = makePerspectiveMatrix(radians(60.0), this.canvas.width / this.canvas.height, 0.1, 10000.0);

    mvMatrix = new Matrix4.identity();
    mvMatrix = mvMatrix.translate(new Vector3(0.0, 0.0, 0.0));
    mvMatrix = mvMatrix.multiply(sphereRotationMatrix);

    gl.activeTexture(webgl.TEXTURE0);
    gl.bindTexture(webgl.TEXTURE_2D, sphereTexture);
    gl.uniform1i(samplerUniform, 0);
    gl.bindBuffer(webgl.ARRAY_BUFFER, sphereVertexPositionBuffer);
    gl.vertexAttribPointer(vertexPositionAttribute, 3, webgl.FLOAT, false, 0, 0);
    gl.bindBuffer(webgl.ARRAY_BUFFER, sphereVertexTextureCoordBuffer);
    gl.vertexAttribPointer(textureCoordAttribute, 2, webgl.FLOAT, false, 0, 0);
    gl.bindBuffer(webgl.ELEMENT_ARRAY_BUFFER, sphereVertexIndexBuffer);
    gl.uniformMatrix4fv(pMatrixUniform, false, pMatrix.storage);
    gl.uniformMatrix4fv(mvMatrixUniform, false, mvMatrix.storage);

    gl.drawElements(webgl.TRIANGLES, numIndices, webgl.UNSIGNED_SHORT, 0);

    window.requestAnimationFrame((num time) {
      this.update();
    });
  }

  void run() {
    window.requestAnimationFrame((num time) {
      this.update();
    });
    this.running = true;
  }
}

void main() {
  PhotosphereViewer demo = new PhotosphereViewer();
  if (demo.init()) {
    demo.run();
  } else {
    document.query('body').appendHtml("""<p>Sorry, your browser probably doesn\'t support WebGL.
      For more information visit
      <a href="http://get.webgl.org/" target="_blank">http://get.webgl.org/</a>.</p>""");
  }
}