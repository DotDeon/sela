import AppKit
import Browsing
import Favicons
import SidebarModel

/// Favourites as a grid of icon tiles, shared by every space.
@MainActor
final class FavoritesGridView: NSView, NSCollectionViewDataSource, NSCollectionViewDelegate {
    static let columns = 4
    static let tileHeight: CGFloat = 52
    static let spacing: CGFloat = 8
    static let emptyHeight: CGFloat = 30

    let collectionView = FavoritesCollectionView()
    private let emptyHint = NSTextField(labelWithString: "Drag tabs here to make favourites")
    private let model: BrowserWindowModel
    private let favicons: FaviconStore
    private var favoriteIDs: [ItemID] = []
    private var heightConstraint: NSLayoutConstraint!

    init(model: BrowserWindowModel, favicons: FaviconStore) {
        self.model = model
        self.favicons = favicons
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: Self.tileHeight))

        let layout = NSCollectionViewGridLayout()
        layout.maximumNumberOfColumns = Self.columns
        layout.minimumInteritemSpacing = Self.spacing
        layout.minimumLineSpacing = Self.spacing
        layout.minimumItemSize = NSSize(width: 40, height: Self.tileHeight)
        layout.maximumItemSize = NSSize(width: 120, height: Self.tileHeight)
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FavoriteTile.self, forItemWithIdentifier: FavoriteTile.identifier)
        collectionView.registerForDraggedTypes([.sidebarItem])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        let menu = NSMenu()
        menu.addItem(menuItem("Remove from Favourites") { [weak self] in self?.removeClickedFavorite() })
        collectionView.menu = menu

        emptyHint.font = .systemFont(ofSize: 11)
        emptyHint.textColor = .tertiaryLabelColor
        emptyHint.alignment = .center

        for view in [collectionView, emptyHint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        heightConstraint = heightAnchor.constraint(equalToConstant: Self.tileHeight)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyHint.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyHint.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightConstraint,
        ])
        registerForDraggedTypes([.sidebarItem])
        keepObserving { [weak self] in self?.update() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private var document: SidebarDocument { model.sidebar.document }

    private func update() {
        let ids = document.item(document.favoritesContainerID)?.childIDs ?? []
        if ids != favoriteIDs {
            favoriteIDs = ids
            collectionView.reloadData()
        } else {
            for case let tile as FavoriteTile in collectionView.visibleItems() {
                if let index = collectionView.indexPath(for: tile)?.item { configure(tile, at: index) }
            }
        }
        let rows = (ids.count + Self.columns - 1) / Self.columns
        heightConstraint.constant = ids.isEmpty
            ? Self.emptyHeight
            : CGFloat(rows) * Self.tileHeight + CGFloat(max(rows - 1, 0)) * Self.spacing
        emptyHint.isHidden = !ids.isEmpty

        let selected = model.selectedItemID.flatMap { ids.firstIndex(of: $0) }
        let wanted: Set<IndexPath> = selected.map { [IndexPath(item: $0, section: 0)] } ?? []
        if collectionView.selectionIndexPaths != wanted {
            collectionView.selectionIndexPaths = wanted
        }
    }

    private func configure(_ tile: FavoriteTile, at index: Int) {
        guard favoriteIDs.indices.contains(index), let item = document.item(favoriteIDs[index]),
              case .tab(let info) = item.kind
        else { return }
        let state = model.liveTab(for: item.id)?.state
        let page = state?.url ?? info.savedURL
        let title = sidebarTitle(for: item, liveState: state.map { ($0.url, displayTitle(for: $0)) })
        tile.imageView?.image = favicons.image(forPage: page) ?? letterImage(for: page?.host() ?? title, size: 22, color: .systemGray)
        tile.view.toolTip = title
    }

    private func removeClickedFavorite() {
        guard let index = collectionView.clickedIndex, favoriteIDs.indices.contains(index) else { return }
        model.sidebar.unpin(favoriteIDs[index], in: model.selectedSpaceID)
    }

    // MARK: Data source and delegate

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        favoriteIDs.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let tile = collectionView.makeItem(withIdentifier: FavoriteTile.identifier, for: indexPath) as! FavoriteTile
        configure(tile, at: indexPath.item)
        return tile
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let index = indexPaths.first?.item, favoriteIDs.indices.contains(index) else { return }
        model.select(favoriteIDs[index])
    }

    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
        favoriteIDs.indices.contains(indexPath.item) ? pasteboardItem(for: favoriteIDs[indexPath.item]) : nil
    }

    func collectionView(_ collectionView: NSCollectionView, validateDrop info: any NSDraggingInfo, proposedIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        guard let id = draggedItemID(info), document.canMove(id, to: document.favoritesContainerID) else { return [] }
        dropOperation.pointee = .before
        return .move
    }

    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: any NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        guard let id = draggedItemID(info) else { return false }
        var index = indexPath.item
        if let old = favoriteIDs.firstIndex(of: id), old < index { index -= 1 }
        return (try? model.sidebar.move(id, to: document.favoritesContainerID, at: index)) != nil
    }

    // Drops on the empty area, where the collection view has no items to drop between.

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let id = draggedItemID(sender), document.canMove(id, to: document.favoritesContainerID) else { return [] }
        return .move
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let id = draggedItemID(sender) else { return false }
        model.sidebar.addToFavorites(id)
        return true
    }
}

/// Remembers which tile a right-click landed on, for the context menu.
final class FavoritesCollectionView: NSCollectionView {
    private(set) var clickedIndex: Int?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        clickedIndex = indexPathForItem(at: point)?.item
        return clickedIndex == nil ? nil : super.menu(for: event)
    }
}

/// One favourite: a rounded tile with the site's icon.
final class FavoriteTile: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("favorite")

    override func loadView() {
        let tile = NSView()
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 10
        let icon = NSImageView()
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: tile.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
        ])
        view = tile
        imageView = icon
        updateBackground()
    }

    override var isSelected: Bool {
        didSet { updateBackground() }
    }

    private func updateBackground() {
        let dark = view.effectiveAppearance.isDark
        let alpha: CGFloat = isSelected ? (dark ? 0.22 : 0.85) : (dark ? 0.08 : 0.35)
        view.layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
    }
}
