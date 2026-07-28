import AppKit

struct NotchGeometryService {
    func notchRect(for screen: NSScreen) -> CGRect? {
        guard
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let leftEdge = leftArea.maxX
        let rightEdge = rightArea.minX
        let width = rightEdge - leftEdge
        guard width >= 40 else { return nil }

        let height = max(screen.safeAreaInsets.top, screen.frame.maxY - leftArea.minY)
        guard height >= 8 else { return nil }
        return CGRect(
            x: leftEdge,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    static func estimatedNotchRect(
        screenFrame: CGRect,
        leftAuxiliaryArea: CGRect?,
        rightAuxiliaryArea: CGRect?,
        safeAreaTop: CGFloat
    ) -> CGRect? {
        guard let leftAuxiliaryArea, let rightAuxiliaryArea else { return nil }
        let width = rightAuxiliaryArea.minX - leftAuxiliaryArea.maxX
        guard width >= 40 else { return nil }
        let height = max(safeAreaTop, screenFrame.maxY - leftAuxiliaryArea.minY)
        return CGRect(
            x: leftAuxiliaryArea.maxX,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }
}
