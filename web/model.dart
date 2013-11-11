library model;
import 'dart:html';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:convert'; 
import 'dart:async';

class Model {
  webgl.RenderingContext _gl;
  IndexBuffer _indexBuffer;
  List<VertexBuffer> _vertexBuffers;
  int _drawMode;
  bool _empty = true;

  Model(this._gl);
  
  void loadBuffers(drawMode, indexBuf, vertexBuf) {
    this._empty         = false;
    this._drawMode      = drawMode;
    this._indexBuffer   = indexBuf;
    this._vertexBuffers = vertexBuf;
  }
  
  Future loadBufObjUrl(String url) {
    return HttpRequest.getString(url)
      ..then((response) => loadBufObj(response));
  }
  
  void loadBufObj(String str) {
    this._empty = false;
    this._drawMode = webgl.TRIANGLES;

    var bufObj = JSON.decode(str);
    
    _indexBuffer   = new IndexBuffer(_gl, bufObj["indices"]);
    _vertexBuffers = new List<VertexBuffer>();
    for (var attr in bufObj["attributes"].keys) {
      int nElements = bufObj["metadata"]["elements"][attr];
      var attrData  = bufObj["attributes"][attr]; 
      _vertexBuffers.add(new VertexBuffer(_gl, nElements, attrData, attr));  
    }
  }
    
  void bind() {
    if (_empty) return;
    
    if (_indexBuffer != null)
      _indexBuffer.bind();
    
    for (int i = 0; i < _vertexBuffers.length; i++) {
      _vertexBuffers[i].bind(i);
      _gl.enableVertexAttribArray(i);
    }
  }

  void draw() {
    if (_empty) return;

    if (_indexBuffer != null)
      _indexBuffer.draw(_drawMode);
    else
      _vertexBuffers[0].draw(_drawMode);
  }
}

class IndexBuffer {
  webgl.RenderingContext _gl;
  webgl.Buffer _buf;
  final int count;

  IndexBuffer(this._gl, List<int> indices) :
    count = indices.length
  {
    _buf = _gl.createBuffer();
    _gl.bindBuffer(webgl.ELEMENT_ARRAY_BUFFER, _buf);
    _gl.bufferDataTyped(webgl.ELEMENT_ARRAY_BUFFER,
        new Uint16List.fromList(indices), webgl.STATIC_DRAW);
  }
  
  void bind() => _gl.bindBuffer(webgl.ELEMENT_ARRAY_BUFFER, _buf);
  void draw(int mode) => _gl.drawElements(mode, count, webgl.UNSIGNED_SHORT, 0);
}

class VertexBuffer {
  webgl.RenderingContext _gl;
  webgl.Buffer _buf;
  final int count, size;
  final String name;
  
  VertexBuffer(this._gl, size, List<double> elements, [this.name = null]) :
    this.size = size,
    count = elements.length ~/ size
  {
    if (elements.length % size != 0)
      throw new Exception("Number of elements is not a multiple of size.");
    
    _buf = _gl.createBuffer();
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _buf);
    _gl.bufferDataTyped(webgl.ARRAY_BUFFER,
        new Float32List.fromList(elements), webgl.STATIC_DRAW);
  }
  
  void bind(int index) {
    _gl.bindBuffer(webgl.ARRAY_BUFFER, _buf);
    _gl.vertexAttribPointer(index, size, webgl.FLOAT, false, 0, 0);
  }
  
  void draw(int mode) => _gl.drawArrays(mode, 0, count);
}
