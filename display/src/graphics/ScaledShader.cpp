#include "graphics/ScaledShader.h"

#include <QColor>
#include <QFile>
#include <QMatrix4x4>
#include <QMetaProperty>
#include <QQmlFile>
#include <QQuickWindow>
#include <QVector2D>
#include <QVector3D>
#include <QVector4D>
#include <rhi/qrhi.h>

#include <array>
#include <cstring>
#include <memory>

namespace {

const QString kVertexShader = QStringLiteral(":/McFly/shaders/scaled.vert.qsb");

QShader readShader(const QString &path)
{
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QShader::fromSerialized(file.readAll());
}

QVector2D toVec2(const QVariant &v)
{
    switch (v.metaType().id()) {
    case QMetaType::QSizeF: {
        const QSizeF s = v.toSizeF();
        return QVector2D(float(s.width()), float(s.height()));
    }
    case QMetaType::QSize: {
        const QSize s = v.toSize();
        return QVector2D(float(s.width()), float(s.height()));
    }
    case QMetaType::QPointF:
    case QMetaType::QPoint:
        return QVector2D(v.toPointF());
    default:
        return v.value<QVector2D>();
    }
}

QVector4D toVec4(const QVariant &v)
{
    if (v.metaType().id() == QMetaType::QColor) {
        // Premultiplied, as ShaderEffect hands colours over.
        const QColor c = v.value<QColor>().toRgb();
        const float a = float(c.alphaF());
        return QVector4D(float(c.redF()) * a, float(c.greenF()) * a, float(c.blueF()) * a, a);
    }
    return v.value<QVector4D>();
}

// One value into the block, std140, at the offset the shader's reflection gave.
void pack(const QVariant &v, int type, char *dst)
{
    std::array<float, 16> f{};
    int n = 0;
    switch (type) {
    case QShaderDescription::Float:
        f[0] = v.toFloat();
        n = 1;
        break;
    case QShaderDescription::Int: {
        const qint32 i = v.toInt();
        std::memcpy(dst, &i, sizeof i);
        return;
    }
    case QShaderDescription::Vec2: {
        const QVector2D x = toVec2(v);
        f = {x.x(), x.y()};
        n = 2;
        break;
    }
    case QShaderDescription::Vec3: {
        const QVector3D x = v.value<QVector3D>();
        f = {x.x(), x.y(), x.z()};
        n = 3;
        break;
    }
    case QShaderDescription::Vec4: {
        const QVector4D x = toVec4(v);
        f = {x.x(), x.y(), x.z(), x.w()};
        n = 4;
        break;
    }
    case QShaderDescription::Mat4: {
        const QMatrix4x4 m = v.value<QMatrix4x4>();
        std::memcpy(f.data(), m.constData(), 16 * sizeof(float));
        n = 16;
        break;
    }
    default:
        return;
    }
    std::memcpy(dst, f.data(), size_t(n) * sizeof(float));
}

} // namespace

// Lives on the render thread: a triangle over the whole colour buffer, the
// fragment shader on it, the uniform block uploaded each time it draws (it
// only draws when the item changed).
class ScaledShaderRenderer : public QQuickRhiItemRenderer
{
public:
    void initialize(QRhiCommandBuffer *) override
    {
        if (m_rhi != rhi()) {
            m_pipeline.reset();
            m_srb.reset();
            m_ubuf.reset();
            m_vbuf.reset();
            m_rhi = rhi();
        }
        if (!m_vertex.isValid()) {
            m_vertex = readShader(kVertexShader);
            if (!m_vertex.isValid())
                qWarning("ScaledShader: can't read %s", qPrintable(kVertexShader));
        }
        if (!m_vbuf) {
            // qt_TexCoord0 is (0, 0) at the top left, whichever way the
            // backend's y runs (QQuickRhiItem flips the picture for GL).
            const float s = m_rhi->isYUpInNDC() ? 1.0f : -1.0f;
            const float xy[3][2] = {{-1, -1}, {3, -1}, {-1, 3}};
            for (int i = 0; i < 3; ++i) {
                m_vertices[i * 4 + 0] = xy[i][0];
                m_vertices[i * 4 + 1] = xy[i][1];
                m_vertices[i * 4 + 2] = (xy[i][0] + 1) / 2;
                m_vertices[i * 4 + 3] = (1 - s * xy[i][1]) / 2;
            }
            m_vbuf.reset(m_rhi->newBuffer(QRhiBuffer::Immutable, QRhiBuffer::VertexBuffer, sizeof m_vertices));
            m_vbuf->create();
            m_vbufUploaded = false;
        }
        // A new colour buffer (the item was resized) may come with another
        // kind of pass.
        if (m_pipeline && (m_pipeline->sampleCount() != renderTarget()->sampleCount()
                           || !m_pipeline->renderPassDescriptor()->isCompatible(renderTarget()->renderPassDescriptor())))
            m_pipelineDirty = true;
    }

    void synchronize(QQuickRhiItem *item) override
    {
        auto *shader = static_cast<ScaledShader *>(item);
        if (shader->m_shaderSerial != m_serial) {
            m_serial = shader->m_shaderSerial;
            m_fragment = shader->m_status == ScaledShader::Compiled ? shader->m_shader : QShader();
            m_pipelineDirty = true;
        }
        m_block = shader->m_block;
    }

    void render(QRhiCommandBuffer *cb) override
    {
        if (m_pipelineDirty)
            build();
        QRhiResourceUpdateBatch *updates = m_rhi->nextResourceUpdateBatch();
        if (m_pipeline) {
            if (!m_vbufUploaded) {
                updates->uploadStaticBuffer(m_vbuf.get(), m_vertices);
                m_vbufUploaded = true;
            }
            updates->updateDynamicBuffer(m_ubuf.get(), 0, quint32(m_block.size()), m_block.constData());
        }
        cb->beginPass(renderTarget(), Qt::transparent, {1.0f, 0}, updates);
        if (m_pipeline) {
            const QSize size = renderTarget()->pixelSize();
            cb->setGraphicsPipeline(m_pipeline.get());
            cb->setViewport(QRhiViewport(0, 0, float(size.width()), float(size.height())));
            cb->setShaderResources();
            const QRhiCommandBuffer::VertexInput input(m_vbuf.get(), 0);
            cb->setVertexInput(0, 1, &input);
            cb->draw(3);
        }
        cb->endPass();
    }

private:
    void build()
    {
        m_pipelineDirty = false;
        m_pipeline.reset();
        m_srb.reset();
        if (!m_vertex.isValid() || !m_fragment.isValid() || m_block.isEmpty())
            return;
        if (!m_ubuf || m_ubuf->size() != quint32(m_block.size())) {
            m_ubuf.reset(m_rhi->newBuffer(QRhiBuffer::Dynamic, QRhiBuffer::UniformBuffer, quint32(m_block.size())));
            m_ubuf->create();
        }
        m_srb.reset(m_rhi->newShaderResourceBindings());
        m_srb->setBindings({QRhiShaderResourceBinding::uniformBuffer(
            0, QRhiShaderResourceBinding::FragmentStage, m_ubuf.get())});
        m_srb->create();

        m_pipeline.reset(m_rhi->newGraphicsPipeline());
        m_pipeline->setShaderStages({{QRhiShaderStage::Vertex, m_vertex}, {QRhiShaderStage::Fragment, m_fragment}});
        QRhiVertexInputLayout layout;
        layout.setBindings({{4 * sizeof(float)}});
        layout.setAttributes({{0, 0, QRhiVertexInputAttribute::Float2, 0},
                              {0, 1, QRhiVertexInputAttribute::Float2, 2 * sizeof(float)}});
        m_pipeline->setVertexInputLayout(layout);
        m_pipeline->setSampleCount(renderTarget()->sampleCount());
        m_pipeline->setShaderResourceBindings(m_srb.get());
        m_pipeline->setRenderPassDescriptor(renderTarget()->renderPassDescriptor());
        if (!m_pipeline->create()) {
            qWarning("ScaledShader: the shader's pipeline couldn't be made");
            m_pipeline.reset();
        }
    }

    QRhi *m_rhi = nullptr;
    QShader m_vertex;
    QShader m_fragment;
    int m_serial = -1;
    QByteArray m_block;
    bool m_pipelineDirty = true;
    float m_vertices[12] = {};
    bool m_vbufUploaded = false;
    std::unique_ptr<QRhiBuffer> m_vbuf;
    std::unique_ptr<QRhiBuffer> m_ubuf;
    std::unique_ptr<QRhiShaderResourceBindings> m_srb;
    std::unique_ptr<QRhiGraphicsPipeline> m_pipeline;
};

ScaledShader::ScaledShader(QQuickItem *parent)
    : QQuickRhiItem(parent)
{
}

QQuickRhiItemRenderer *ScaledShader::createRenderer()
{
    return new ScaledShaderRenderer;
}

QSGNode *ScaledShader::updatePaintNode(QSGNode *node, UpdatePaintNodeData *data)
{
    // Software rendering has nothing to draw with: draw nothing, quietly
    // (the components show their fallback once they see it's software).
    if (!window() || !window()->rhi()) {
        delete node;
        return nullptr;
    }
    return QQuickRhiItem::updatePaintNode(node, data);
}

void ScaledShader::setFragmentShader(const QUrl &url)
{
    if (url == m_url)
        return;
    m_url = url;
    emit fragmentShaderChanged();
    if (isComponentComplete())
        reload();
}

void ScaledShader::setUniformSource(QObject *source)
{
    if (source == m_source)
        return;
    m_source = source;
    emit uniformSourceChanged();
    if (isComponentComplete())
        reload();
}

void ScaledShader::componentComplete()
{
    QQuickRhiItem::componentComplete();
    reload();
}

void ScaledShader::reload()
{
    load();
    bindUniforms();
    readUniforms();
}

void ScaledShader::setStatus(Status status)
{
    if (status == m_status)
        return;
    m_status = status;
    emit statusChanged();
}

// Reads the shader and maps its uniform block onto this item's properties.
void ScaledShader::load()
{
    m_uniforms.clear();
    m_block.clear();
    m_shader = {};
    ++m_shaderSerial;
    if (m_url.isEmpty()) {
        setStatus(Uncompiled);
        return;
    }
    const QShader shader = readShader(QQmlFile::urlToLocalFileOrQrc(m_url));
    const QList<QShaderDescription::UniformBlock> blocks = shader.description().uniformBlocks();
    const auto block = std::find_if(blocks.cbegin(), blocks.cend(),
                                    [](const QShaderDescription::UniformBlock &b) { return b.binding == 0; });
    if (!shader.isValid() || block == blocks.cend()) {
        qWarning("ScaledShader: %s is not a shader with a uniform block at binding 0", qPrintable(m_url.toString()));
        setStatus(Error);
        update();
        return;
    }
    m_block = QByteArray(block->size, '\0');
    for (const QShaderDescription::BlockVariable &member : block->members) {
        char *at = m_block.data() + member.offset;
        if (member.name == "qt_Matrix") {
            pack(QMatrix4x4(), member.type, at);
        } else if (member.name == "qt_Opacity") {
            pack(1.0, member.type, at);
        } else {
            const int property = source()->metaObject()->indexOfProperty(member.name.constData());
            if (property < 0)
                qWarning("ScaledShader: %s's uniform %s has no property of that name",
                         qPrintable(m_url.fileName()), member.name.constData());
            m_uniforms.append({member.offset, int(member.type), property});
        }
    }
    m_shader = shader;
    setStatus(Compiled);
    update();
}

void ScaledShader::bindUniforms()
{
    for (const QMetaObject::Connection &c : std::as_const(m_connections))
        disconnect(c);
    m_connections.clear();
    const QMetaMethod changed = staticMetaObject.method(staticMetaObject.indexOfSlot("uniformChanged()"));
    QObject *from = source();
    for (const Uniform &u : std::as_const(m_uniforms)) {
        if (u.property < 0)
            continue;
        const QMetaProperty property = from->metaObject()->property(u.property);
        if (property.hasNotifySignal())
            m_connections.append(connect(from, property.notifySignal(), this, changed));
    }
}

// Several uniforms change together on a clock's tick: read them once, before
// the frame (polish), not once each.
void ScaledShader::uniformChanged()
{
    if (m_uniformsDirty)
        return;
    m_uniformsDirty = true;
    polish();
}

void ScaledShader::updatePolish()
{
    QQuickRhiItem::updatePolish();
    if (!m_uniformsDirty)
        return;
    m_uniformsDirty = false;
    readUniforms();
}

void ScaledShader::readUniforms()
{
    if (m_block.isEmpty())
        return;
    QObject *from = source();
    for (const Uniform &u : std::as_const(m_uniforms)) {
        if (u.property >= 0)
            pack(from->metaObject()->property(u.property).read(from), u.type, m_block.data() + u.offset);
    }
    update();
}
