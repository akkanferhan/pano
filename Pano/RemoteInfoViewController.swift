import CoreImage.CIFilterBuiltins
import UIKit

/// "Telefondan kontrol" ekranı: QR kod, adres ve PIN.
final class RemoteInfoViewController: UIViewController {
    var onDisable: (() -> Void)?

    private let server = RemoteServer.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 0.97)

        let title = label("Telefondan kontrol", size: 56, weight: .bold)
        let info = label("iPhone kamerasıyla QR kodu okut. Telefon ve Apple TV aynı Wi-Fi ağında olmalı.\n" +
                         "Telefondan adres gönderebilir, metin yazabilir, dokunmatik alanla imleci yönetebilirsin.",
                         size: 28, weight: .regular, color: UIColor(white: 1, alpha: 0.7))
        let qr = UIImageView()
        qr.contentMode = .scaleAspectFit
        qr.layer.magnificationFilter = .nearest
        qr.backgroundColor = .white
        qr.layer.cornerRadius = 18
        qr.layer.masksToBounds = true

        let address = server.address
        let addressLabel = label(address ?? "Ağ adresi bulunamadı — Apple TV Wi-Fi/Ethernet'e bağlı mı?",
                                 size: 34, weight: .semibold)
        let pinLabel = label("PIN: \(server.pin)", size: 28, weight: .medium, color: UIColor(white: 1, alpha: 0.6))
        if let address { qr.image = Self.qrImage(address) }

        let close = UIButton(type: .system)
        close.setTitle("Kapat", for: .normal)
        close.addAction(UIAction { [weak self] _ in self?.dismiss(animated: true) }, for: .primaryActionTriggered)
        let disable = UIButton(type: .system)
        disable.setTitle("Telefondan kontrolü kapat", for: .normal)
        disable.addAction(UIAction { [weak self] _ in
            self?.dismiss(animated: true) { self?.onDisable?() }
        }, for: .primaryActionTriggered)

        let buttons = UIStackView(arrangedSubviews: [close, disable])
        buttons.spacing = 40
        let text = UIStackView(arrangedSubviews: [title, info, addressLabel, pinLabel, buttons])
        text.axis = .vertical
        text.spacing = 30
        text.alignment = .leading
        let row = UIStackView(arrangedSubviews: [qr, text])
        row.spacing = 80
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(row)
        NSLayoutConstraint.activate([
            qr.widthAnchor.constraint(equalToConstant: 420),
            qr.heightAnchor.constraint(equalToConstant: 420),
            text.widthAnchor.constraint(equalToConstant: 900),
            row.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor = .white) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.numberOfLines = 0
        return l
    }

    static func qrImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)) else { return nil }
        // Kenarda beyaz boşluk (okunabilirlik için)
        let padded = output.composited(over: CIImage(color: .white).cropped(to: output.extent.insetBy(dx: -36, dy: -36)))
        guard let cg = CIContext().createCGImage(padded, from: padded.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
