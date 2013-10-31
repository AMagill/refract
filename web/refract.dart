import 'dart:html';
import 'dart:web_gl' as webgl;
import 'package:vector_math/vector_math.dart';
import 'dart:typed_data';
import 'model.dart';
import 'shader.dart';
import 'frame_buffer.dart';
import 'texture.dart';

class Refract {
  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _objShader, _envShader;
  FrameBuffer _backFbo;
  Vector3 camPos;
  Model model, bigQuad;
  Texture backTex;
  int renderMode = 0;
  
  Refract(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl", 
        {'antialias':false, 'depth':true});
    camPos  = new Vector3(0.0, 0.0, -5.0);
    
    _gl.clearColor(0.5, 0.5, 0.5, 1.0);

    
    // Load stuff!
    model = new Model(_gl)
    ..loadJsonUrl("monkey-2.js").then((_) => render());
    
    bigQuad = new Model(_gl)
      ..loadBuffers(webgl.TRIANGLES,
        new IndexBuffer(_gl, [0,1,2, 0,2,3]),
        [new VertexBuffer(_gl, 2, [-1.0,-1.0,  1.0,-1.0,  1.0,1.0,  -1.0,1.0])]);
    
    backTex = new Texture(_gl)
      ..loadImageUrl("env_1024.jpg").then((_) => render());

    
    // Initialize stuff!
    Matrix4 pMatrix = makePerspectiveMatrix(radians(45.0), _width / _height, 3.0, 7.0);
    //Matrix4 pMatrix = makeOrthographicMatrix(-2.0, 2.0, -2.0, 2.0, 3.0, 7.0);

    _initShaders();
    _backFbo = new FrameBuffer(_gl, _width, _height); 
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _backFbo.imageTex);
    _gl.activeTexture(webgl.TEXTURE1);
    _gl.bindTexture(webgl.TEXTURE_2D, backTex.texture);
    _objShader.use();
    _gl.uniform1i(_objShader.uniforms['uBackSampler'], 0);
    _gl.uniform2f(_objShader.uniforms['uViewSize'], _width, _height);
    _gl.uniformMatrix4fv(_objShader.uniforms['uProjMatrix'],  false, pMatrix.storage);
    _envShader.use();
    _gl.uniform2f(_envShader.uniforms['uViewSize'], _width, _height);
    _gl.uniformMatrix4fv(_envShader.uniforms['uProjMatrix'],  false, pMatrix.storage);
    _gl.uniform1i(_envShader.uniforms['uBackSampler'], 1);
    
    _gl.enable(webgl.DEPTH_TEST);
        
  }

  void _initShaders() {
    String vsObject = """
precision mediump float;
precision mediump int;

attribute vec3 aVertexPosition;
attribute vec3 aVertexNormal;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;
uniform int  uViewMode;

varying vec3 vNormal;

void main(void) {
  gl_Position = uProjMatrix * uModelViewMatrix * 
    vec4(aVertexPosition, 1.0);
  vNormal = aVertexNormal;
}
    """;
    
    String fsObject = """
precision mediump float;
precision mediump int;

uniform mat4      uProjMatrix;
uniform int       uViewMode;
uniform vec2      uViewSize;
uniform sampler2D uBackSampler;

varying vec3 vNormal;

void main(void) {
  if (uViewMode == 0)         // Composite
    gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
  else if (uViewMode == 1)    // Normals
    gl_FragColor = vec4((vNormal+1.0)*0.5, 1.0);
  else if (uViewMode == 2)    // Depth
    gl_FragColor = vec4(gl_FragCoord.zzz, 1.0);
  else if (uViewMode == 3) {  // Thickness
    float a = texture2D(uBackSampler, 
      (gl_FragCoord.xy) / uViewSize).a - gl_FragCoord.z;
    gl_FragColor =  vec4(a, a, a, 1.0);
  }
  else //if (uViewMode == 4)    // Combined depth
    gl_FragColor = vec4((vNormal+1.0)*0.5, gl_FragCoord.z);
}
    """;
    
    _objShader = new Shader(_gl, vsObject, fsObject, 
        {'aVertexPosition':0, 'aVertexNormal':1});
    
    String vsEnvironment = """
precision mediump float;
precision mediump int;

attribute vec3 aPosition;

varying vec4 vPosition;

void main(void) {
  gl_Position = vPosition = vec4(aPosition.xy, 0.99, 1.0);
}
    """;
    
    String fsEnvironment = """
precision mediump float;
precision mediump int;

uniform mat4      uInvMvpMatrix;
uniform vec2      uViewSize;
uniform sampler2D uBackSampler;

varying vec4 vPosition;

vec2 vecToER(vec4 dir) {
  const float PI = 3.1415926535898;
  vec3 ndir = normalize(dir.xyz / dir.w);
  return vec2(atan(ndir.x, ndir.z) / (2.0*PI), acos(ndir.y) / PI);
}

void main(void) {
  //vec2 coord = gl_FragCoord.xy/uViewSize;
  vec2 coord = vecToER(uInvMvpMatrix * vPosition);
  gl_FragColor = texture2D(uBackSampler, coord);
}
    """;

    _envShader = new Shader(_gl, vsEnvironment, fsEnvironment, 
        {'aPosition':0});
}
    
  void render() {
    
    // Generate matrices
    var mv = new Matrix4.identity()
      ..translate(0.0, 0.0, -5.0)//camPos.z)
      ..rotateY(radians(camPos.x))
      ..rotateX(radians(camPos.y));
    Matrix4 pMatrix = makePerspectiveMatrix(radians(-camPos.z*9.0), _width / _height, 3.0, 7.0);

    // Set them in the object shader
    _objShader.use();
    _gl.uniformMatrix4fv(_objShader.uniforms['uModelViewMatrix'], false, 
        new Float32List.fromList(mv.storage));
    _gl.uniformMatrix4fv(_objShader.uniforms['uProjMatrix'],  false, pMatrix.storage);

    // Render back view
    bool skip = false;
    switch (renderMode) {
      case 0:   // Composite
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 4);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, _backFbo.fbo);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 5:   // Thickness
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 4);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, _backFbo.fbo);
        _gl.clearColor(0, 0, 0, 1);
        break;
      case 1:   // Front normals
      case 3:   // Front depth
        skip = true;
        break;
      case 2:   // Back normals
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 1);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 4:   // Back depth
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 2);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
        _gl.clearColor(0, 0, 0, 1);
        break;
    }
    if (!skip) {
      _gl.clearDepth(0);
      _gl.depthFunc(webgl.GEQUAL);
      _gl.viewport(0, 0, _backFbo.width, _backFbo.height);
      _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
                webgl.RenderingContext.DEPTH_BUFFER_BIT);
      model.bind();
      model.draw();
    }
    
    // Now the front view
    skip = false;
    switch (renderMode) {
      case 0:   // Composite
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 0);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 1:   // Front normals
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 1);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 2:   // Back normals
      case 4:   // Back depth
        skip = true;
        break;
      case 3:   // Front depth
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 2);
        _gl.clearColor(1, 1, 1, 1);
        break;
      case 5:   // Thickness
        _gl.uniform1i(_objShader.uniforms['uViewMode'], 3);
        _gl.clearColor(0, 0, 0, 1);
        break;
    }
    if (!skip) {
      _gl.clearDepth(1);
      _gl.depthFunc(webgl.LESS);
      _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
      _gl.viewport(0, 0, _width, _height);
      _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
                webgl.RenderingContext.DEPTH_BUFFER_BIT);
      model.bind();
      model.draw();
    }
    
    // Draw the environment map
    if (renderMode == 0) {
      _envShader.use();
      Matrix4 invMvpMatrix = pMatrix * mv;
      invMvpMatrix.invert();
      _gl.uniformMatrix4fv(_envShader.uniforms['uInvMvpMatrix'], false, 
          invMvpMatrix.storage);      
      
      _gl.depthMask(false);
      bigQuad.bind();
      bigQuad.draw();
      _gl.depthMask(true);
    }    

  }
  
  void rotate(Vector3 delta) {
    camPos += delta;
  }
  
}



Refract scene;
bool isDown = false;
Vector3 lastMouse;

void main() {
  var canvas = document.querySelector("#glCanvas")
    ..onMouseMove.listen(onMouseMove)
    ..onMouseWheel.listen(onMouseWheel)
    ..onMouseDown.listen((e) {isDown = true;})
    ..onMouseUp.listen((e) {isDown = false;});
  
  document.querySelector("#viewMode") as SelectElement
    ..onChange.listen(onViewModeChange);
  
  scene = new Refract(canvas);
  scene.render();
}

void onMouseMove(MouseEvent e) {
  Vector3 curMouse = new Vector3(
      e.offset.x.toDouble(), 
      -e.offset.y.toDouble(), 
      0.0);
  
  if (isDown && lastMouse != null) {
    scene.rotate(lastMouse - curMouse);
    scene.render();
  }
  
  lastMouse = curMouse;
}

void onMouseWheel(WheelEvent e) {
  scene.camPos.z += e.wheelDeltaY.toDouble() / 480.0;
  scene.render();
}

void onViewModeChange(Event e) {
  scene.renderMode = (document.querySelector("#viewMode") as SelectElement).selectedIndex;
  scene.render();
}