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
  Shader _shader;
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
      //..loadImageUrl("env_1024.jpg").then((_) => render());
      ..loadImageUrl("testPattern.png").then((_) => render());

    
    // Initialize stuff!
    _initShaders();
    _backFbo = new FrameBuffer(_gl, _width, _height); 
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _backFbo.imageTex);
    _gl.activeTexture(webgl.TEXTURE1);
    _gl.bindTexture(webgl.TEXTURE_2D, backTex.texture);
    _shader.use();
    _gl.uniform1i(_shader.uniforms['uBackSampler'], 0);
    _gl.uniform1i(_shader.uniforms['uEnvSampler'], 1);
    _gl.uniform2f(_shader.uniforms['uViewSize'], _width, _height);
    
    _gl.enable(webgl.DEPTH_TEST);
        
  }

  void _initShaders() {
    String vsObject = """
precision mediump float;
precision mediump int;

attribute vec3 aPosition;
attribute vec3 aNormal;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;
uniform int  uViewMode;
uniform mat4 uTModelView;
uniform mat4 uInvProj;

varying vec3 vNormal;
varying vec3 vEyeDirection;

void main(void) {
  
  vNormal = aNormal;

  if (uViewMode == 5) {
    gl_Position = vec4(aPosition.xy, 0.99, 1.0);
    vEyeDirection = mat3(uTModelView) * (uInvProj * vec4(aPosition,1.0)).xyz;
  } else {
    gl_Position = uProjMatrix * uModelViewMatrix *  vec4(aPosition, 1.0);
    vEyeDirection = vec3(uModelViewMatrix[3] * uModelViewMatrix) + aPosition;
  }
}
    """;
    
    String fsObject = """
precision mediump float;
precision mediump int;

uniform mat4      uProjMatrix;
uniform int       uViewMode;
uniform vec2      uViewSize;
uniform sampler2D uBackSampler;
uniform sampler2D uEnvSampler;

varying vec3 vNormal;
varying vec3 vEyeDirection;

vec4 textureOrtho(sampler2D sampler, vec3 dir) {
  const float PI  = 3.1415926535898;
  const float PI2 = PI * 2.0;

  vec2 coord = vec2(atan(dir.z, dir.x) / PI2, acos(dir.y) / PI);
  return texture2D(sampler, coord);
}

void main(void) {
  if (uViewMode == 0) {       // Composite
    vec3 rayDir = normalize(vEyeDirection);
    //rayDir = refract(rayDir, vec3(0.0,0.0,1.0), 1.0);
    gl_FragColor = textureOrtho(uEnvSampler, rayDir) + vec4(0.1, 0.1, 0.1, 0.0);
  }
  else if (uViewMode == 1)    // Normals
    gl_FragColor = vec4((vNormal+1.0)*0.5, 1.0);
  else if (uViewMode == 2)    // Depth
    gl_FragColor = vec4(gl_FragCoord.zzz, 1.0);
  else if (uViewMode == 3) {  // Thickness
    float a = texture2D(uBackSampler, 
      (gl_FragCoord.xy) / uViewSize).a - gl_FragCoord.z;
    gl_FragColor =  vec4(a, a, a, 1.0);
  }
  else if (uViewMode == 4)    // Combined depth
    gl_FragColor = vec4((vNormal+1.0)*0.5, gl_FragCoord.z);
  else { // if (uViewMode == 5) // Environment
    vec3 rayDir = normalize(vEyeDirection);
    gl_FragColor = textureOrtho(uEnvSampler, rayDir);
  }
}
    """;
    
    _shader = new Shader(_gl, vsObject, fsObject, 
        {'aPosition':0, 'aNormal':1});

}
    
  void render() {
    
    // Generate matrices
    var mvMatrix = new Matrix4.identity()
      ..translate(0.0, 0.0, -5.0)//camPos.z)
      ..rotateY(radians(camPos.x))
      ..rotateX(radians(camPos.y));
    Matrix4 pMatrix = makePerspectiveMatrix(radians(-camPos.z*9.0), _width / _height, 3.0, 7.0);
    //Matrix4 pMatrix = makeOrthographicMatrix(-2.0, 2.0, -2.0, 2.0, 3.0, 7.0);
    Matrix4 transMV = mvMatrix.transposed();
    Matrix4 invProj = pMatrix.clone();
    invProj.invert();

    // Set them in the shader
    _gl.uniformMatrix4fv(_shader.uniforms['uModelViewMatrix'], false, 
        mvMatrix.storage);
    _gl.uniformMatrix4fv(_shader.uniforms['uProjMatrix'],  false, 
        pMatrix.storage);
    _gl.uniformMatrix4fv(_shader.uniforms['uInvProj'], false, 
        invProj.storage);
    _gl.uniformMatrix4fv(_shader.uniforms['uTModelView'], false, 
        transMV.storage);

    // Render back view
    bool skip = false;
    switch (renderMode) {
      case 0:   // Composite
        _gl.uniform1i(_shader.uniforms['uViewMode'], 4);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, _backFbo.fbo);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 5:   // Thickness
        _gl.uniform1i(_shader.uniforms['uViewMode'], 4);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, _backFbo.fbo);
        _gl.clearColor(0, 0, 0, 1);
        break;
      case 1:   // Front normals
      case 3:   // Front depth
        skip = true;
        break;
      case 2:   // Back normals
        _gl.uniform1i(_shader.uniforms['uViewMode'], 1);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 4:   // Back depth
        _gl.uniform1i(_shader.uniforms['uViewMode'], 2);
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
        _gl.uniform1i(_shader.uniforms['uViewMode'], 0);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 1:   // Front normals
        _gl.uniform1i(_shader.uniforms['uViewMode'], 1);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        break;
      case 2:   // Back normals
      case 4:   // Back depth
        skip = true;
        break;
      case 3:   // Front depth
        _gl.uniform1i(_shader.uniforms['uViewMode'], 2);
        _gl.clearColor(1, 1, 1, 1);
        break;
      case 5:   // Thickness
        _gl.uniform1i(_shader.uniforms['uViewMode'], 3);
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
      _gl.uniform1i(_shader.uniforms['uViewMode'], 5);
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