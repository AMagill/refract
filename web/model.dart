library model;
import 'dart:html';
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:convert'; 
import 'dart:async';
import 'dart:math';

class Model {
  webgl.RenderingContext _gl;
  IndexBuffer _indexBuffer;
  List<VertexBuffer> _vertexBuffers;
  int _drawMode;
  bool _empty = true;

  Model(this._gl) :
    _vertexBuffers = new List<VertexBuffer>();
  
  void loadBuffers(drawMode, indexBuf, vertexBuf) {
    this._empty         = false;
    this._drawMode      = drawMode;
    freeBufs();
    this._indexBuffer   = indexBuf;
    this._vertexBuffers.addAll(vertexBuf);
  }
  
  Future loadBufObjUrl(String url) {
    return HttpRequest.getString(url)
      ..then((response) => loadBufObj(response));
  }
  
  void loadBufObj(String str) {
    this._empty = false;
    this._drawMode = webgl.TRIANGLES;
    freeBufs();

    var bufObj = JSON.decode(str);
        
    _indexBuffer   = new IndexBuffer(_gl, bufObj["indices"]);
    for (var attr in bufObj["attributes"].keys) {
      int nElements = bufObj["metadata"]["elements"][attr];
      var attrData  = bufObj["attributes"][attr]; 
      _vertexBuffers.add(new VertexBuffer(_gl, nElements, attrData, attr));  
    }
  }
  
  void generateCube(double size) {
    this._empty = false;
    this._drawMode = webgl.TRIANGLES;
    freeBufs();
    
    final l = -size/2.0, r = size/2.0;
    _vertexBuffers.add(new VertexBuffer(_gl, 3, [
      l, l, l,    l, l, r,    l, r, r,    l, r, l,      // -X face
      r, l, r,    r, l, l,    r, r, l,    r, r, r,      // +X face
      l, l, l,    r, l, l,    r, l, r,    l, l, r,      // -Y face
      l, r, r,    r, r, r,    r, r, l,    l, r, l,      // +Y face
      r, l, l,    l, l, l,    l, r, l,    r, r, l,      // -Z face
      l, l, r,    r, l, r,    r, r, r,    l, r, r],     // +Z face
      "Position"));
    _vertexBuffers.add(new VertexBuffer(_gl, 3, [
      -1.0,  0.0,  0.0,    -1.0,  0.0,  0.0,    -1.0,  0.0,  0.0,    -1.0,  0.0,  0.0,    // -X face
       1.0,  0.0,  0.0,     1.0,  0.0,  0.0,     1.0,  0.0,  0.0,     1.0,  0.0,  0.0,    // +X face
       0.0, -1.0,  0.0,     0.0, -1.0,  0.0,     0.0, -1.0,  0.0,     0.0, -1.0,  0.0,    // -Y face
       0.0,  1.0,  0.0,     0.0,  1.0,  0.0,     0.0,  1.0,  0.0,     0.0,  1.0,  0.0,    // +Y face
       0.0,  0.0, -1.0,     0.0,  0.0, -1.0,     0.0,  0.0, -1.0,     0.0,  0.0, -1.0,    // -Z face
       0.0,  0.0,  1.0,     0.0,  0.0,  1.0,     0.0,  0.0,  1.0,     0.0,  0.0,  1.0],   // +Z face
       "Normal"));
    _vertexBuffers.add(new VertexBuffer(_gl, 1, 
        new List.filled(24, size), "Normal thick"));
    _indexBuffer = new IndexBuffer(_gl, 
      [ 0, 1, 2, 0, 2, 3,  4, 5, 6, 4, 6, 7, 
        8, 9,10, 8,10,11, 12,13,14,12,14,15, 
       16,17,18,16,18,19, 20,21,22,20,22,23]); 
  }
  
  void generateSphere(double r, int nLat, int nLon) {
    this._empty = false;
    this._drawMode = webgl.TRIANGLES;
    freeBufs();
    
    final radLat = PI / (nLat - 1);
    final radLon = 2.0 * PI / nLon;
    var vertPos = [], vertNorm = [], indices = [];
    for (int j = 0; j < nLat; j++) {
      double y = cos(j * radLat);
      for (int i = 0; i < nLon; i++) {
        double x = sin(i * radLon) * sin(j * radLat);
        double z = cos(i * radLon) * sin(j * radLat);
        vertPos.addAll([x*r,y*r,z*r]);
        vertNorm.addAll([x,y,z]);
        
        if (j > 0) {
          final a = (i>0) ? (j*nLon)+i-1 : ((j+1)*nLon)-1,
              b = (j*nLon)+i,
              c = a - nLon,
              d = b - nLon;
          indices.addAll([a, b, d, a, d, c]);
        }
      }
    }
    
    _vertexBuffers.add(new VertexBuffer(_gl, 3, vertPos, "Position"));
    _vertexBuffers.add(new VertexBuffer(_gl, 3, vertNorm, "Normal"));
    _vertexBuffers.add(new VertexBuffer(_gl, 1,
        new List.filled(nLat*nLon, 2.0*r), "Normal thick"));
    _indexBuffer = new IndexBuffer(_gl, indices);
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
  
  void freeBufs() {
    if (_indexBuffer != null) {
      _indexBuffer.free();
      _indexBuffer = null;
    }
    for (var buf in _vertexBuffers) 
      if (buf != null) buf.free();
    _vertexBuffers.clear();

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
  
  void free() {
    _gl.deleteBuffer(_buf);
    _buf = 0 as webgl.Buffer;
  }
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
  
  void free() {
    _gl.deleteBuffer(_buf);
    _buf = 0 as webgl.Buffer;
  }
}
