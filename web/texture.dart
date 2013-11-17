library texture;
import 'dart:web_gl' as webgl;
import 'dart:html';
import 'dart:async';

class Texture {
  webgl.RenderingContext _gl;
  bool _empty = true;
  webgl.Texture texture;
  int _bindingPoint;
  
  Texture(webgl.RenderingContext this._gl);
  
  Future loadImageUrl(String url) {
    Completer completer = new Completer();
    
    ImageElement imgElem = new ImageElement();
    imgElem
      ..onLoad.listen((_) {
        loadImage(imgElem);
        completer.complete(Null);
      })
      ..onError.listen((_) {
        completer.completeError(Null);
      })
      ..src = url;
    
    return completer.future;
  }
  
  void loadImage(ImageElement img) {
    _bindingPoint = webgl.TEXTURE_2D;
    texture = _gl.createTexture();
    _gl.activeTexture(webgl.TEXTURE3);
    _gl.bindTexture(_bindingPoint, texture);
    _gl.texParameteri(_bindingPoint, webgl.TEXTURE_MIN_FILTER, webgl.LINEAR);
    _gl.texParameteri(_bindingPoint, webgl.TEXTURE_MAG_FILTER, webgl.LINEAR);
    _gl.texImage2DImage(_bindingPoint, 0, webgl.RGB, 
        webgl.RGB, webgl.UNSIGNED_BYTE, img);
  }
  
  void bind() {
    if (texture != null)
      _gl.bindTexture(_bindingPoint, texture);
  }
}