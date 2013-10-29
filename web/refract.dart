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

    // Initialize stuff!
    _initShaders();
    _backFbo = new FrameBuffer(_gl, _width, _height); 
    _gl.bindTexture(webgl.TEXTURE_2D, _backFbo.imageTex);
    _gl.uniform1i(_shader.uniforms['uBackSampler'], 0);
    _gl.uniform2f(_shader.uniforms['uViewSize'], _width, _height);
    
    Matrix4 pMatrix = makePerspectiveMatrix(radians(45.0), _width / _height, 3.0, 7.0);
    //Matrix4 pMatrix = makeOrthographicMatrix(-2.0, 2.0, -2.0, 2.0, 3.0, 7.0);
    _gl.uniformMatrix4fv(_shader.uniforms['uProjMatrix'],  false, pMatrix.storage);
    
    _gl.enable(webgl.DEPTH_TEST);

    model = new Model.empty();  // Just until it loads
    HttpRequest.getString("monkey-2.js").then((response) {
      model = new Model.fromJsonFast(_gl, response);
      render();
    });
    
    /*backTex = new Texture.empty();  // Just until it loads
    ImageElement img = new ImageElement();
    img.onLoad.listen((_) {
      
    });*/
    HttpRequest.getString("monkey-2.js").then((response) {
      model = new Model.fromJsonFast(_gl, response);
      render();
    });
    
    bigQuad = new Model(_gl, webgl.TRIANGLES,
        new IndexBuffer(_gl, [0,1,2, 0,2,3]),
        [new VertexBuffer(_gl, 2, [-1.0,-1.0,  1.0,-1.0,  1.0,1.0,  -1.0,1.0])]);
        
  }
  
  void _initShaders() {
    String vsSource = """
precision mediump float;
precision mediump int;

attribute vec3 aVertexPosition;
attribute vec3 aVertexNormal;

uniform mat4 uProjMatrix;
uniform mat4 uModelViewMatrix;
uniform int  uViewMode;

varying vec3 vNormal;

void main(void) {
  if (uViewMode == 5)
    gl_Position = vec4(aVertexPosition.xy, 0.99, 1.0);
  else
    gl_Position = uProjMatrix * uModelViewMatrix * 
      vec4(aVertexPosition, 1.0);
  vNormal = aVertexNormal;
}
    """;
    
    String fsSource = """
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
  else if (uViewMode == 4)    // Combined depth
    gl_FragColor = vec4((vNormal+1.0)*0.5, gl_FragCoord.z);
  else {                      // Environment map
    gl_FragColor = vec4(gl_FragCoord.xy / uViewSize, 0.0, 1.0);
  }
}
    """;
    
    _shader = new Shader(_gl, vsSource, fsSource, 
        {'aVertexPosition':0, 'aVertexNormal':1});
  }
    
  void render() {
    // Set modelview
    var mv = new Matrix4.identity()
      ..translate(0.0, 0.0, -5.0)//camPos.z)
      ..rotateY(radians(camPos.x))
      ..rotateX(radians(camPos.y));
    _gl.uniformMatrix4fv(_shader.uniforms['uModelViewMatrix'], false, 
        new Float32List.fromList(mv.storage));

    Matrix4 pMatrix = makePerspectiveMatrix(radians(-camPos.z*9.0), _width / _height, 3.0, 7.0);
    _gl.uniformMatrix4fv(_shader.uniforms['uProjMatrix'],  false, pMatrix.storage);

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
    
/*    _gl.clearDepth(1);
    _gl.depthFunc(webgl.LESS);
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
    _gl.clear(webgl.RenderingContext.COLOR_BUFFER_BIT | 
              webgl.RenderingContext.DEPTH_BUFFER_BIT);
*/
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