#pragma once

#include <QQuickImageProvider>

// QR codes for QML: Image { source: "image://qr/" + encodeURIComponent(text) }.
// A story's detail view shows one so the article can be opened on a phone,
// and the pairing screen shows the code. Drawn with Nayuki's generator
// (display/third_party/qrcodegen), dark modules on a white quiet zone, at the
// requested size with crisp edges.
class QrImageProvider : public QQuickImageProvider
{
public:
    QrImageProvider();
    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

    // The modules of `text` as an image, one pixel per module plus a quiet
    // zone of `quiet` modules, or a null image when the text is too long.
    static QImage modules(const QString &text, int quiet = 4);
};
