/// A photo-library album (PhotoKit `PHAssetCollection`), as surfaced by
/// [NsfwDetector.listAlbums]. Lightweight, read-only descriptor — used to
/// populate an album picker for the move/add/remove operations.
class PhotoAlbum {
  const PhotoAlbum({
    required this.id,
    required this.title,
    required this.count,
    this.isUserAlbum = true,
  });

  /// Stable platform identifier (`PHAssetCollection.localIdentifier`) — pass
  /// this back to the album operations as `albumId`/`toAlbumId`.
  final String id;

  /// Human-readable album name (may be empty for untitled albums).
  final String title;

  /// Number of assets currently in the album.
  final int count;

  /// `true` for user-created albums (editable: assets can be added/removed).
  /// `false` for smart/system collections — those reject membership changes.
  final bool isUserAlbum;

  /// Parses the channel wire-shape (`{id, title, count, isUserAlbum}`).
  factory PhotoAlbum.fromMap(Map<dynamic, dynamic> map) {
    return PhotoAlbum(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
      isUserAlbum: map['isUserAlbum'] as bool? ?? true,
    );
  }

  @override
  String toString() =>
      'PhotoAlbum(id: $id, title: "$title", count: $count, '
      'isUserAlbum: $isUserAlbum)';
}
