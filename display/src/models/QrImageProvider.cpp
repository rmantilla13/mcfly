#include "QrImageProvider.h"

#include "qrcodegen.hpp"

#include <QUrl>

QrImageProvider::QrImageProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}

QImage QrImageProvider::modules(const QString &text, int quiet)
{
    using qrcodegen::QrCode;
    QrCode qr = QrCode::encodeText("", QrCode::Ecc::MEDIUM);
    try {
        // Medium correction: a 1200-character link still fits (version 40);
        // anything longer is not a URL anyone would scan.
        qr = QrCode::encodeText(text.toUtf8().constData(), QrCode::Ecc::MEDIUM);
    } catch (const std::exception &) {
        return {};
    }
    const int size = qr.getSize();
    QImage image(size + 2 * quiet, size + 2 * quiet, QImage::Format_RGB32);
    image.fill(Qt::white);
    for (int y = 0; y < size; ++y) {
        for (int x = 0; x < size; ++x) {
            if (qr.getModule(x, y))
                image.setPixel(x + quiet, y + quiet, qRgb(0x1C, 0x1C, 0x1F));
        }
    }
    return image;
}

QImage QrImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    // The id arrives percent-decoded once by the engine; a URL's own escapes
    // survive because QML encodes the whole text first.
    const QString text = QUrl::fromPercentEncoding(id.toUtf8());
    QImage image = modules(text);
    if (image.isNull()) {
        image = QImage(1, 1, QImage::Format_RGB32);
        image.fill(Qt::white);
    }
    // Whole multiples of the module size keep the edges crisp; the Image
    // element centres it in whatever it is given.
    const int side = qMax(requestedSize.width(), requestedSize.height());
    if (side > 0) {
        const int scale = qMax(1, side / image.width());
        image = image.scaled(image.width() * scale, image.height() * scale, Qt::IgnoreAspectRatio, Qt::FastTransformation);
    }
    if (size)
        *size = image.size();
    return image;
}
