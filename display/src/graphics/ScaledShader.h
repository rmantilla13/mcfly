#pragma once

#include <QByteArray>
#include <QList>
#include <QPointer>
#include <QQuickRhiItem>
#include <QUrl>
#include <rhi/qshader.h>

class ScaledShaderRenderer;

// A fragment shader drawn at a fraction of its item's size and scaled up:
// what a ShaderEffect under `layer.enabled` with a smaller
// `layer.textureSize` draws, in one frame per change instead of two. Each
// time a layer's picture changes Qt draws one more frame after it, the same
// again (QSGRhiLayer asks for another frame whenever it grabs), so a
// full-screen sky moving 30 times a second cost the panel 60 frames; on the
// Pi 5 the screen saver's extra 30 were about a quarter of its GPU time.
//
// The shader is one written for ShaderEffect (shaders/*.frag): its uniform
// block at binding 0 opens with qt_Matrix and qt_Opacity, and its other
// uniforms are properties of the same names, read whenever one of them
// changes (vec2 from a size, point or vector2d, vec4 from a vector4d or a
// colour, premultiplied as ShaderEffect hands it over). They are this
// item's own, or `uniformSource`'s: a ShaderEffect kept for the full-size
// case and hidden while this draws, so the uniforms are written once.
// qt_TexCoord0 runs 0..1 from the top left. qt_Opacity is 1 and the item's
// opacity is applied as the picture is drawn, as with a layer.
//
//   ScaledShader {
//       anchors.fill: parent
//       fixedColorBufferWidth: Math.ceil(width * 0.5)     // pixels, as layer.textureSize
//       fixedColorBufferHeight: Math.ceil(height * 0.5)
//       readonly property real time: clock.time
//       fragmentShader: "qrc:/McFly/shaders/dawn.frag.qsb"
//   }
//
// It draws one triangle over the colour buffer (shaders/scaled.vert). A
// `vertexShader` of its own is drawn as one strip per pixel column instead,
// each vertex given its column's centre u at location 2, the same for all
// of the column's vertices: what a shader works out from the column alone
// can be worked out there once a column and handed on, exactly, rather than
// in every pixel of it (shaders/arc.vert). It declares the fragment
// shader's uniform block.
//
// Opaque unless `alphaBlending` is on (a premultiplied picture with
// transparent parts, like a tile's rounded corners). Needs the RHI: under
// software rendering it draws nothing, so keep a fallback beside it.
class ScaledShader : public QQuickRhiItem
{
    Q_OBJECT
    Q_PROPERTY(QUrl fragmentShader READ fragmentShader WRITE setFragmentShader NOTIFY fragmentShaderChanged)
    // Empty (the default): one triangle. Else drawn a strip per column.
    Q_PROPERTY(QUrl vertexShader READ vertexShader WRITE setVertexShader NOTIFY vertexShaderChanged)
    // Where the uniforms are read from; null (the default) is this item.
    Q_PROPERTY(QObject *uniformSource READ uniformSource WRITE setUniformSource NOTIFY uniformSourceChanged)
    Q_PROPERTY(Status status READ status NOTIFY statusChanged)

public:
    // As ShaderEffect's: Error when the shader can't be read, has no
    // uniform block this item can fill, or its vertex stage isn't its match.
    enum Status { Uncompiled, Compiled, Error };
    Q_ENUM(Status)

    explicit ScaledShader(QQuickItem *parent = nullptr);

    QUrl fragmentShader() const { return m_url; }
    void setFragmentShader(const QUrl &url);
    QUrl vertexShader() const { return m_vertexUrl; }
    void setVertexShader(const QUrl &url);
    QObject *uniformSource() const { return m_source; }
    void setUniformSource(QObject *source);
    Status status() const { return m_status; }

    // The uniform block as the shader reads it (tests).
    QByteArray uniformBlock() const { return m_block; }

signals:
    void fragmentShaderChanged();
    void vertexShaderChanged();
    void uniformSourceChanged();
    void statusChanged();

protected:
    QQuickRhiItemRenderer *createRenderer() override;
    QSGNode *updatePaintNode(QSGNode *node, UpdatePaintNodeData *data) override;
    void componentComplete() override;
    void updatePolish() override;

private slots:
    void uniformChanged();

private:
    friend class ScaledShaderRenderer;

    struct Uniform {
        int offset = 0;
        int type = 0;       // QShaderDescription::VariableType
        int property = -1;  // index in source()'s metaObject()
    };

    QObject *source() { return m_source ? m_source.data() : this; }
    void reload();
    void load();
    void bindUniforms();
    void readUniforms();
    void setStatus(Status status);

    QUrl m_url;
    QUrl m_vertexUrl;
    QPointer<QObject> m_source;
    Status m_status = Uncompiled;
    QShader m_shader;
    QShader m_vertexShader;     // empty: the renderer's triangle
    int m_shaderSerial = 0;     // bumped with each new shader, for the renderer
    QList<Uniform> m_uniforms;
    QByteArray m_block;
    bool m_uniformsDirty = false;
    QList<QMetaObject::Connection> m_connections;
};
