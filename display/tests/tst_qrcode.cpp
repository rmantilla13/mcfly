#include <QtTest>

#include "models/QrImageProvider.h"

// The QR codes behind image://qr/…: well-formed modules for a link, and the
// provider's crisp scaling.
class TestQrCode : public QObject
{
    Q_OBJECT

    // A finder pattern: a 7×7 square ring, dark-light-dark, at (x, y).
    static bool finderAt(const QImage &image, int x, int y)
    {
        for (int j = 0; j < 7; ++j) {
            for (int i = 0; i < 7; ++i) {
                const bool edge = i == 0 || i == 6 || j == 0 || j == 6;
                const bool centre = i >= 2 && i <= 4 && j >= 2 && j <= 4;
                const bool dark = qGray(image.pixel(x + i, y + j)) < 128;
                if (dark != (edge || centre))
                    return false;
            }
        }
        return true;
    }

private slots:
    void encodesALink()
    {
        const QImage qr = QrImageProvider::modules(QStringLiteral("https://mcfly.bot/pair?code=123456"), 4);
        QVERIFY(!qr.isNull());
        // Version 3 at most for a short link: 29 modules plus the quiet zone.
        const int size = qr.width() - 8;
        QVERIFY2(size >= 21 && size <= 33 && size % 4 == 1, qPrintable(QString::number(size)));
        QCOMPARE(qr.height(), qr.width());
        // Quiet zone is white all round.
        for (int i = 0; i < qr.width(); ++i) {
            QCOMPARE(qGray(qr.pixel(i, 0)), 255);
            QCOMPARE(qGray(qr.pixel(0, i)), 255);
            QCOMPARE(qGray(qr.pixel(i, qr.height() - 1)), 255);
        }
        // The three finder patterns.
        QVERIFY(finderAt(qr, 4, 4));
        QVERIFY(finderAt(qr, 4 + size - 7, 4));
        QVERIFY(finderAt(qr, 4, 4 + size - 7));
        // A different text gives a different code.
        QVERIFY(QrImageProvider::modules(QStringLiteral("https://mcfly.bot/pair?code=654321"), 4) != qr);
    }

    void refusesWhatCannotFit()
    {
        QVERIFY(QrImageProvider::modules(QString(5000, QLatin1Char('x'))).isNull());
    }

    void providerScalesToWholeModules()
    {
        QrImageProvider provider;
        QSize size;
        const QImage image = provider.requestImage(QStringLiteral("https%3A%2F%2Fmcfly.bot%2Fpair%3Fcode%3D123456"), &size, QSize(300, 300));
        QVERIFY(!image.isNull());
        QCOMPARE(size, image.size());
        const QImage base = QrImageProvider::modules(QStringLiteral("https://mcfly.bot/pair?code=123456"));
        QCOMPARE(image.width() % base.width(), 0);
        QVERIFY(image.width() <= 300 && image.width() > 300 - base.width());
        // Scaled without smoothing: still only black and white.
        QVERIFY(qGray(image.pixel(image.width() / 2, 0)) == 255);
        // Nothing to encode: a white pixel, not a crash.
        QVERIFY(!provider.requestImage(QString(), nullptr, QSize(100, 100)).isNull());
    }
};

QTEST_GUILESS_MAIN(TestQrCode)
#include "tst_qrcode.moc"
