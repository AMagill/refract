import 'dart:html';
import 'dart:web_gl' as webgl;
import 'package:vector_math/vector_math.dart';
import 'model.dart';
import 'shader.dart';
import 'frame_buffer.dart';
import 'texture.dart';

class Refract {
  int _width, _height;
  webgl.RenderingContext _gl;
  Shader _refractShader, _normalShader, _depthShader, _backShader, 
         _thickShader, _nThickShader, _envShader;
  FrameBuffer _backFbo;
  Vector3 camPos;
  List<Model> allModels;
  Model model, bigQuad;
  List<Texture> allBackgrounds;
  Texture backTex;
  int renderMode = 0;
  
  Refract(CanvasElement canvas) {
    _width  = canvas.width;
    _height = canvas.height;
    _gl     = canvas.getContext("experimental-webgl", 
        {'antialias':false, 'depth':true});
    camPos  = new Vector3(0.0, 0.0, -4.0);
    
    _gl.clearColor(0.5, 0.5, 0.5, 1.0);

    // Load stuff!
    allModels = new List<Model>();
    allModels.add(new Model(_gl)
      ..loadBufObjUrl("monkey-2.bof").then((_) => render()));
    allModels.add(new Model(_gl)
      ..generateSphere(1.0, 32, 32));
    allModels.add(new Model(_gl)
    ..generateCube(1.5));
    model = allModels[0];
    
    bigQuad = new Model(_gl)
      ..loadBuffers(webgl.TRIANGLES,
        new IndexBuffer(_gl, [0,1,2, 0,2,3]),
        [new VertexBuffer(_gl, 2, [-1.0,-1.0,  1.0,-1.0,  1.0,1.0,  -1.0,1.0])]);
    
    allBackgrounds = new List<Texture>();
    allBackgrounds.add(new Texture(_gl)
      ..loadImageUrl("env_1024.jpg").then((_) => render()));
    allBackgrounds.add(new Texture(_gl)
      ..loadImageUrl("testPattern.png"));
    backTex = allBackgrounds[0];

    
    // Initialize stuff!  FBO,
    _backFbo = new FrameBuffer(_gl, _width, _height);
    // textures, 
    _gl.activeTexture(webgl.TEXTURE0);
    _gl.bindTexture(webgl.TEXTURE_2D, _backFbo.imageTex);
    _gl.activeTexture(webgl.TEXTURE1);
    _gl.bindTexture(webgl.TEXTURE_2D, backTex.texture);
    // and shaders.
    _initShaders();
    _refractShader.use();
    _gl.uniform1i(_refractShader.uniforms['uBackSampler'], 0);
    _gl.uniform1i(_refractShader.uniforms['uEnvSampler'], 1);
    _gl.uniform2f(_refractShader.uniforms['uViewSize'], _width, _height);
    _thickShader.use();
    _gl.uniform1i(_thickShader.uniforms['uBackSampler'], 0);
    _gl.uniform2f(_thickShader.uniforms['uViewSize'], _width, _height);    
    _envShader.use();
    _gl.uniform1i(_envShader.uniforms['uEnvSampler'], 1);
    
    
    _gl.enable(webgl.DEPTH_TEST);
        
  }

  void _initShaders() {
    String vsRefract = """
precision mediump float;
precision mediump int;

attribute vec3  aPosition;
attribute vec3  aNormal;
attribute float aNThick;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;

varying vec3  vNormal;
varying vec3  vEyeDirection;
varying vec3  vEyeLocation;
varying float vNormThick;

void main(void) {
  vNormal       = aNormal;
  vNormThick    = aNThick;
  vEyeDirection = vec3(uModelViewMatrix[3] * uModelViewMatrix) + aPosition;
  vEyeLocation  = aPosition;
  gl_Position   = uProjMatrix * uModelViewMatrix *  vec4(aPosition, 1.0);
}
    """;
    
    String fsRefract = """
precision mediump float;
precision mediump int;

uniform mat4      uProjMatrix;
uniform mat4      uModelViewMatrix;
uniform vec2      uViewSize;
uniform sampler2D uBackSampler;
uniform sampler2D uEnvSampler;
uniform int       uRefractMode;

varying vec3  vNormal;
varying vec3  vEyeDirection;
varying vec3  vEyeLocation;
varying float vNormThick;

vec4 textureOrtho(sampler2D sampler, vec3 dir) {
  const float PI  = 3.1415926535898;
  const float PI2 = PI * 2.0;

  vec2 coord = vec2(atan(dir.z, dir.x) / PI2, acos(dir.y) / PI);
  return texture2D(sampler, coord);
}

float winZToEyeZ(float winZ, mat4 projMat) {
  return projMat[3][2] / (2.0*winZ + projMat[2][2] - 1.0);
}

void main(void) {
  const float IOR = 1.2;

  // First refraction
  vec3 nEyeDir = normalize(vEyeDirection);
  vec3 nNormal = normalize(vNormal);
  vec3 rayDir = refract(nEyeDir, nNormal, 1.0/IOR);
  if (uRefractMode == 1) {
    gl_FragColor = textureOrtho(uEnvSampler, rayDir);
    return;
  }

  // Second refraction
  float backWinZ   = texture2D(uBackSampler, (gl_FragCoord.xy) / uViewSize).a;
  float eyeThick   = winZToEyeZ(backWinZ,       uProjMatrix) -
                     winZToEyeZ(gl_FragCoord.z, uProjMatrix);
  float angleRatio = acos(dot(rayDir,  -vNormal)) / 
                     acos(dot(nEyeDir, -vNormal));
  float estThick   = angleRatio * eyeThick + (1.0-angleRatio) * vNormThick;
  vec3  estExitPt  = vEyeLocation + rayDir * estThick; 
  vec4  estExitPos = uProjMatrix * uModelViewMatrix * vec4(estExitPt, 1.0);
  vec2  estExitPx  = (estExitPos.xy / estExitPos.w / 2.0) + 0.5;
  vec4  exitNormal = texture2D(uBackSampler, estExitPx) * 2.0 - 1.0;
  vec3  rayDir2    = refract(rayDir, -exitNormal.xyz, IOR);
  if (all(equal(rayDir2, vec3(0.0))))
    rayDir2 = reflect(rayDir, -exitNormal.xyz);

  gl_FragColor = textureOrtho(uEnvSampler, rayDir2);
}
    """;
    
    _refractShader = new Shader(_gl, vsRefract, fsRefract, 
        {'aPosition':0, 'aNormal':1, 'aNThick':2});


    String vsNormal = """
precision mediump float;
precision mediump int;

attribute vec3  aPosition;
attribute vec3  aNormal;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;

varying vec3  vNormal;

void main(void) {
  vNormal = (aNormal+1.0)*0.5;
  gl_Position = uProjMatrix * uModelViewMatrix * vec4(aPosition, 1.0);
}
    """;
    
    String fsNormal = """
precision mediump float;
precision mediump int;

varying vec3  vNormal;

void main(void) {
  gl_FragColor = vec4(vNormal, 1.0);
}
    """;
    
    _normalShader = new Shader(_gl, vsNormal, fsNormal, 
        {'aPosition':0, 'aNormal':1});
    
    
    String vsDepth = """
precision mediump float;
precision mediump int;

attribute vec3  aPosition;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;

void main(void) {
  gl_Position = uProjMatrix * uModelViewMatrix *  vec4(aPosition, 1.0);
}
    """;
    
    String fsDepth = """
precision mediump float;
precision mediump int;

void main(void) {
  gl_FragColor = vec4(gl_FragCoord.zzz, 1.0);
}
    """;
    
    _depthShader = new Shader(_gl, vsDepth, fsDepth, 
        {'aPosition':0});
    
    String vsBack = """
precision mediump float;
precision mediump int;

attribute vec3  aPosition;
attribute vec3  aNormal;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;

varying vec3  vNormal;

void main(void) {
  vNormal = (aNormal+1.0)*0.5;
  gl_Position = uProjMatrix * uModelViewMatrix *  vec4(aPosition, 1.0);
}
    """;
    
    String fsBack = """
precision mediump float;
precision mediump int;

varying vec3  vNormal;

void main(void) {
    gl_FragColor = vec4(vNormal, gl_FragCoord.z);
}
    """;
    
    _backShader = new Shader(_gl, vsBack, fsBack, 
        {'aPosition':0, 'aNormal':1});


    String vsThick = """
precision mediump float;
precision mediump int;

attribute vec3  aPosition;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;

void main(void) {
  gl_Position = uProjMatrix * uModelViewMatrix *  vec4(aPosition, 1.0);
}
    """;
    
    String fsThick = """
precision mediump float;
precision mediump int;

uniform mat4      uProjMatrix;
uniform vec2      uViewSize;
uniform sampler2D uBackSampler;

float winZToEyeZ(float winZ, mat4 projMat) {
  return projMat[3][2] / (2.0*winZ + projMat[2][2] - 1.0);
}

void main(void) {
  float winZf = texture2D(uBackSampler, (gl_FragCoord.xy) / uViewSize).a;
  float winZn = gl_FragCoord.z;
  float eyeZf = winZToEyeZ(winZf, uProjMatrix);
  float eyeZn = winZToEyeZ(winZn, uProjMatrix);
  float a = (eyeZf - eyeZn) / 2.0;
  gl_FragColor =  vec4(a, a, a, 1.0);
}
    """;
    
    _thickShader = new Shader(_gl, vsThick, fsThick, 
        {'aPosition':0});    
    
    String vsNThick = """
precision mediump float;
precision mediump int;

attribute vec3  aPosition;
attribute float aNThick;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;

varying float vNThick;

void main(void) {
  vNThick = aNThick;
  gl_Position = uProjMatrix * uModelViewMatrix *  vec4(aPosition, 1.0);
}
    """;
    
    String fsNThick = """
precision mediump float;
precision mediump int;

varying float vNThick;

void main(void) {
  float t = vNThick / 2.0;
  gl_FragColor = vec4(t,t,t,1.0);
}
    """;
    
    _nThickShader = new Shader(_gl, vsNThick, fsNThick, 
        {'aPosition':0, 'aNThick':2});

    String vsEnvironment = """
precision mediump float;
precision mediump int;

attribute vec3  aPosition;

uniform mat4 uTModelView;
uniform mat4 uInvProj;

varying vec3  vEyeDirection;

void main(void) {
  gl_Position = vec4(aPosition.xy, 0.99, 1.0);
  vEyeDirection = mat3(uTModelView) * (uInvProj * vec4(aPosition,1.0)).xyz;
}
    """;
    
    String fsEnvironment = """
precision mediump float;
precision mediump int;

uniform sampler2D uEnvSampler;

varying vec3  vEyeDirection;

vec4 textureOrtho(sampler2D sampler, vec3 dir) {
  const float PI  = 3.1415926535898;
  const float PI2 = PI * 2.0;

  vec2 coord = vec2(atan(dir.z, dir.x) / PI2, acos(dir.y) / PI);
  return texture2D(sampler, coord);
}

void main(void) {
  vec3 rayDir = normalize(vEyeDirection);
  gl_FragColor = textureOrtho(uEnvSampler, rayDir);
}
    """;
    
    _envShader = new Shader(_gl, vsEnvironment, fsEnvironment, 
        {'aPosition':0});
}
    
  void render() {
    // Generate matrices
    var mvMatrix = new Matrix4.identity()
      ..translate(0.0, 0.0, -5.0)
      ..rotateY(radians(camPos.x))
      ..rotateX(radians(camPos.y));
    Matrix4 pMatrix = makePerspectiveMatrix(radians(-camPos.z*9.0), _width / _height, 3.0, 7.0);
    Matrix4 transMV = mvMatrix.transposed();
    Matrix4 invProj = pMatrix.clone();
    invProj.invert();
    
    _gl.activeTexture(webgl.TEXTURE1);
    backTex.bind();
    
    switch (renderMode) {
      case 0:   // Composite two-surface
      case 1:   // Composite one-surface
        // First pass: Normals+depth into FBO
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, _backFbo.fbo);
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        _gl.clearDepth(0);
        _gl.depthFunc(webgl.GEQUAL);
        _gl.viewport(0, 0, _backFbo.width, _backFbo.height);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);

        _backShader.use();
        _gl.uniformMatrix4fv(_backShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_backShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.bind();
        model.draw();

        // Second pass: display
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        _gl.clearDepth(1);
        _gl.depthFunc(webgl.LESS);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
        _gl.viewport(0, 0, _width, _height);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);
        
        _refractShader.use();
        _gl.uniformMatrix4fv(_refractShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_refractShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        _gl.uniform1i(_refractShader.uniforms['uRefractMode'], renderMode);
        model.draw();
        
        // Draw environment
        _envShader.use();
        _gl.uniformMatrix4fv(_envShader.uniforms['uInvProj'],    false, invProj.storage);
        _gl.uniformMatrix4fv(_envShader.uniforms['uTModelView'], false, transMV.storage);
        _gl.depthMask(false);
        bigQuad.bind();
        bigQuad.draw();
        _gl.depthMask(true);
        break;

      case 2:   // Front normals
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        _gl.clearDepth(1);
        _gl.depthFunc(webgl.LESS);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);
        
        _normalShader.use();
        _gl.uniformMatrix4fv(_normalShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_normalShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.bind();
        model.draw();
        break;
        
      case 3:   // Back normals
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        _gl.clearDepth(0);
        _gl.depthFunc(webgl.GEQUAL);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);

        _normalShader.use();
        _gl.uniformMatrix4fv(_normalShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_normalShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.bind();
        model.draw();
        break;
        
      case 4:   // Front depth
        _gl.clearColor(1, 1, 1, 1);
        _gl.clearDepth(1);
        _gl.depthFunc(webgl.LESS);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);

        _depthShader.use();
        _gl.uniformMatrix4fv(_depthShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_depthShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.bind();
        model.draw();
        break;
        
      case 5:   // Back depth
        _gl.clearColor(0, 0, 0, 1);
        _gl.clearDepth(0);
        _gl.depthFunc(webgl.GEQUAL);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);

        _depthShader.use();
        _gl.uniformMatrix4fv(_depthShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_depthShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.bind();
        model.draw();
        break;
        
      case 6:   // Thickness
        // First pass: Normals+depth into FBO
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, _backFbo.fbo);
        _gl.clearColor(0, 0, 0, 1);

        _gl.clearDepth(0);
        _gl.depthFunc(webgl.GEQUAL);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);
        _backShader.use();
        _gl.uniformMatrix4fv(_backShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_backShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.bind();
        model.draw();

        // Second pass: display
        _gl.clearColor(0, 0, 0, 1);
        _gl.clearDepth(1);
        _gl.depthFunc(webgl.LESS);
        _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);
        _thickShader.use();
        _gl.uniformMatrix4fv(_thickShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_thickShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.draw();
        break;
        
      case 7:   // Normal thickness
        _gl.clearColor(0.5, 0.5, 0.5, 1);
        _gl.clearDepth(1);
        _gl.depthFunc(webgl.LESS);
        _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
            webgl.RenderingContext.DEPTH_BUFFER_BIT);
        _nThickShader.use();
        _gl.uniformMatrix4fv(_nThickShader.uniforms['uModelViewMatrix'], false, mvMatrix.storage);
        _gl.uniformMatrix4fv(_nThickShader.uniforms['uProjMatrix'],      false, pMatrix.storage);
        model.bind();
        model.draw();        
        break;
    }

  }
  
  void rotate(Vector3 delta) {
    camPos += delta;
  }
  
  void setModel(int n) {
    model = allModels[n];
  }
  
  void setBackground(int n) {
    backTex = allBackgrounds[n];
  }
  
}



Refract scene;
Vector3 lastMouse;

void main() {
  var canvas = document.querySelector("#glCanvas")
    ..onMouseMove.listen(onMouseMove)
    ..onMouseWheel.listen(onMouseWheel)
    ..onMouseDown.listen((e) {lastMouse = null;})
    ..onTouchMove.listen(onMouseMove)
    ..onTouchEnd.listen((e) {lastMouse = null;});
    
  document.querySelector("#viewMode") as SelectElement
    ..onChange.listen((e) {
      scene.renderMode = (document.querySelector("#viewMode") as SelectElement).selectedIndex;
      scene.render();
    });
  
  document.querySelector("#model") as SelectElement
    ..onChange.listen((e) {
      scene.setModel((document.querySelector("#model") as SelectElement).selectedIndex);
      scene.render();
    });
  
  document.querySelector("#background") as SelectElement
    ..onChange.listen((e) {
      scene.setBackground((document.querySelector("#background") as SelectElement).selectedIndex);
      scene.render();
    });

  scene = new Refract(canvas);
  scene.render();
}

void onMouseMove(var e) {
  Vector3 curMouse;
  bool isDown;
  
  if (e is TouchEvent) {
    e.preventDefault();   // Don't scroll the page
    isDown = true;

    curMouse = new Vector3(
      e.touches[0].client.x,
      -e.touches[0].client.y,
      0.0);
  } else {
    isDown = (e.which == 1);
    
    curMouse = new Vector3(
      e.offset.x.toDouble(), 
      -e.offset.y.toDouble(), 
      0.0);    
  }

  if (isDown && lastMouse != null) {
    scene.rotate(lastMouse - curMouse);
    scene.render();
  }
  
  lastMouse = curMouse;
}

void onMouseWheel(WheelEvent e) {
  scene.camPos.z += e.deltaY.toDouble() / 480.0;
  scene.render();
}
