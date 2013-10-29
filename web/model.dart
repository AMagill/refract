library model;
import 'dart:web_gl' as webgl;
import 'dart:typed_data';
import 'dart:convert'; 

class Model {
  webgl.RenderingContext _gl;
  IndexBuffer _indexBuffer;
  List<VertexBuffer> _vertexBuffers;
  int _drawMode;
  bool _empty = false;

  Model(this._gl, this._drawMode, this._indexBuffer, this._vertexBuffers);
  Model.empty() : this._empty = true;
  
  Model.fromJsonFast(this._gl, String str) :
    this._drawMode = webgl.TRIANGLES
  {
    // Based on https://github.com/mrdoob/three.js/wiki/JSON-Model-format-3.1
    var js = JSON.decode(str);
    
    if (js['metadata']['formatVersion'] != 3.1)
      throw new Exception('Unsupported file format.');

    var faces   = js['faces'];
    var verts   = js['vertices'];
    var normals = js['normals'];
    var colors  = js['colors'];
    var nUvLayers = 0;
    
    for (int i = 0; i < js['uvs'].length; i++)
      if (js['uvs'][i].isNotEmpty()) nUvLayers++;
    
    var indices = new List<int>();
    var outVerts = new List<double>();
    var outNorms = new List<double>();
    
    // Read in all the indices from the face array
    int offset = 0, nVerts = 0;
    while (offset < faces.length) {
      var type = faces[offset++];
      
      bool isQuad         = (type & 1<<0) != 0;
      bool hasMaterial    = (type & 1<<1) != 0;
      bool hasFaceUv      = (type & 1<<2) != 0;
      bool hasVertUv      = (type & 1<<3) != 0;
      bool hasFaceNormal  = (type & 1<<4) != 0;
      bool hasVertNormal  = (type & 1<<5) != 0;
      bool hasFaceColor   = (type & 1<<6) != 0;
      bool hasVertColor   = (type & 1<<7) != 0;
      var ptrs;
      
      if (isQuad) {
        ptrs = [new _UniqueVertIndexes(vert: faces[offset++]),
                new _UniqueVertIndexes(vert: faces[offset++]),
                new _UniqueVertIndexes(vert: faces[offset++]),
                new _UniqueVertIndexes(vert: faces[offset++])];
      } else {
        ptrs = [new _UniqueVertIndexes(vert: faces[offset++]),
                new _UniqueVertIndexes(vert: faces[offset++]),
                new _UniqueVertIndexes(vert: faces[offset++])];
      }
      
      if (hasMaterial) {
        var mat = faces[offset++];
        for (var ptr in ptrs) 
          ptr.mat = mat; 
      }
      
      if (hasFaceUv) {
        var uv = faces[offset++];
        for (var ptr in ptrs)
          ptr.uv = uv;
      }
      
      if (hasVertUv) {
        for (var ptr in ptrs)
          ptr.uv = faces[offset++];
      }
      
      if (hasFaceNormal) {
        var norm = faces[offset++];
        for (var ptr in ptrs)
          ptr.norm = norm;
      }
      
      if (hasVertNormal) {
        for (var ptr in ptrs)
          ptr.norm = faces[offset++];
      }
      
      if (hasFaceColor) {
        var color = faces[offset++];
        for (var ptr in ptrs)
          ptr.color = color;
      }
      
      if (hasVertColor) {
        for (var ptr in ptrs)
          ptr.color = faces[offset++];
      }
      
      // Now keep all the unique combinations
      for (var ptr in ptrs) {
        ptr.index = nVerts++;
        outVerts.add(verts[ptr.vert*3+0].toDouble());
        outVerts.add(verts[ptr.vert*3+1].toDouble());
        outVerts.add(verts[ptr.vert*3+2].toDouble());
        
        outNorms.add(normals[ptr.norm*3+0].toDouble());
        outNorms.add(normals[ptr.norm*3+1].toDouble());
        outNorms.add(normals[ptr.norm*3+2].toDouble());
      }
      
      if (isQuad) {
        indices.add(ptrs[0].index);
        indices.add(ptrs[1].index);
        indices.add(ptrs[2].index);
        indices.add(ptrs[0].index);
        indices.add(ptrs[2].index);
        indices.add(ptrs[3].index);
      } else {
        indices.add(ptrs[0].index);
        indices.add(ptrs[1].index);
        indices.add(ptrs[2].index);
      }
    }
    
    _indexBuffer   = new IndexBuffer(_gl, indices);
    _vertexBuffers = new List<VertexBuffer>();
    _vertexBuffers.add(new VertexBuffer(_gl, 3, outVerts, "vertices"));
    _vertexBuffers.add(new VertexBuffer(_gl, 3, outNorms, "normals"));
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


class _UniqueVertIndexes {
  int vert, mat, norm, id, color, index;
  _UniqueVertIndexes({this.vert: -1, this.mat: -1, this.norm: -1, 
                      this.id:   -1, this.color: -1});
  int get hashCode {
    int result = 17;
    result = 37 * result * vert.hashCode;
    result = 37 * result * mat.hashCode;
    result = 37 * result * norm.hashCode;
    result = 37 * result * id.hashCode;
    result = 37 * result * color.hashCode;
    return result;
  }
  bool operator==(other) {
    return this.vert  == other.vert &&
           this.mat   == other.mat  &&
           this.norm  == other.norm &&
           this.id    == other.id   &&
           this.color == other.color;
  }
}