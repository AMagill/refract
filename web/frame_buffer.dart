library frame_buffer;
import 'dart:web_gl' as webgl;

class FrameBuffer {
  final webgl.RenderingContext _gl;
  final int           width, height;
  final webgl.Framebuffer      fbo;
  final webgl.Texture       imageTex;
  final webgl.Renderbuffer  depthBuf;

  FrameBuffer(webgl.RenderingContext _gl, int this.width, int this.height) :
    this._gl = _gl,
    this.fbo = _gl.createFramebuffer(),
    this.imageTex = _gl.createTexture(),
    this.depthBuf = _gl.createRenderbuffer()
  {
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, fbo);
    
    _gl.bindTexture(webgl.TEXTURE_2D, imageTex);
    _gl.texParameteri(webgl.TEXTURE_2D, webgl.TEXTURE_MAG_FILTER, webgl.NEAREST);
    _gl.texParameteri(webgl.TEXTURE_2D, webgl.TEXTURE_MIN_FILTER, webgl.NEAREST);
    _gl.texImage2DTyped(webgl.TEXTURE_2D, 0, webgl.RGBA, width, height, 0, 
        webgl.RGBA, webgl.UNSIGNED_BYTE, null);
    
    _gl.bindRenderbuffer(webgl.RENDERBUFFER, depthBuf);
    _gl.renderbufferStorage(webgl.RENDERBUFFER, webgl.DEPTH_COMPONENT16, width, height);
    
    _gl.framebufferTexture2D(webgl.FRAMEBUFFER, webgl.COLOR_ATTACHMENT0, 
        webgl.TEXTURE_2D, imageTex, 0);
    _gl.framebufferRenderbuffer(webgl.FRAMEBUFFER, webgl.DEPTH_ATTACHMENT, 
        webgl.RENDERBUFFER, depthBuf);

    _gl.bindTexture(webgl.TEXTURE_2D, null);
    _gl.bindRenderbuffer(webgl.RENDERBUFFER, null);
    _gl.bindFramebuffer(webgl.FRAMEBUFFER, null);
  }
}