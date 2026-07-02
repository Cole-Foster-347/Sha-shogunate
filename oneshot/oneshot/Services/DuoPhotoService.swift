import Foundation
import UIKit
import Supabase

/// Canonical duo-photo storage (Roomeet backend).
///
/// Photos belong to the DUO (equal control, deleted with the duo). They live in the
/// PRIVATE `duo-photos` bucket, laid out per-duo as `duo-photos/<duo_id>/<uuid>.jpg`.
/// `duo_profile.photos[]` stores the STORAGE PATH (not a URL); reads resolve each path
/// to a signed, expiring URL — never a public one (CLAUDE.md §4). Storage RLS
/// (0006_storage_photos.sql) authorizes read/write to the folder via is_duo_member.
///
/// Only the authenticated Supabase client is used — no service-role key on device (§4.1).
@MainActor
final class DuoPhotoService {
    /// Private Storage bucket (created in the dashboard; policies in 0006).
    static let bucket = "duo-photos"
    /// Max photos per duo (§6 / ticket decision).
    static let maxPhotos = 6
    /// Target max upload size: ≤ 1 MB JPEG (§6).
    private static let maxBytes = 1_048_576
    /// Max pixel dimension before quality reduction.
    private static let maxDimension: CGFloat = 2048

    private let supabase = SupabaseConfig.shared.client
    private let authService: AuthService

    init(authService: AuthService) {
        self.authService = authService
    }

    // MARK: - Read

    /// Resolve a stored photo path to a signed, expiring URL.
    /// Accepts either a bucket-relative path (`<duo_id>/<uuid>.jpg`) or one that
    /// includes the bucket prefix (`duo-photos/<duo_id>/<uuid>.jpg`, as photos[] stores).
    /// Expiry defaults to 1h (§12 checklist: expiry ≤ 1h).
    func signedURL(forPath path: String, expiresIn: Int = 3600) async throws -> URL {
        try await supabase.storage
            .from(Self.bucket)
            .createSignedURL(path: objectPath(from: path), expiresIn: expiresIn)
    }

    // MARK: - Upload

    /// Upload one image to the active duo's folder and append its STORAGE PATH to
    /// `duo_profile.photos[]`. Members-only (Storage RLS + duo_profile RLS enforce it).
    /// - Returns: the updated `photos[]` array (paths).
    func addPhoto(_ image: UIImage, toDuo duoId: UUID, existingPhotos: [String]) async throws -> [String] {
        guard existingPhotos.count < Self.maxPhotos else {
            throw DuoPhotoError.tooMany(Self.maxPhotos)
        }

        let data = try Self.compressedJPEG(image)

        // duo-photos/<duo_id>/<uuid>.jpg — object name is the bucket-relative part.
        let objectName = "\(duoId.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await supabase.storage
            .from(Self.bucket)
            .upload(
                objectName,
                data: data,
                options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: false)
            )

        // Store the path WITH the bucket prefix (ticket decision); signedURL strips it.
        let storedPath = "\(Self.bucket)/\(objectName)"
        let updated = existingPhotos + [storedPath]

        try await supabase
            .from("duo_profile")
            .update(["photos": updated])
            .eq("id", value: duoId.uuidString)
            .execute()

        // TODO(analytics): no §10 event covers a duo photo upload; add one if the taxonomy grows.
        return updated
    }

    // MARK: - Remove

    /// Remove one photo from the active duo: delete the Storage object AND drop its
    /// path from `duo_profile.photos[]`. Both-or-neither semantics (ticket §9):
    /// we ALWAYS drop the array entry so it never points at a missing object, and a
    /// Storage "not found" (already gone) is tolerated rather than aborting. Any OTHER
    /// Storage error (e.g. RLS denial) is rethrown BEFORE we touch the array, so we
    /// don't strand a live object with no array reference.
    /// - Parameter path: the stored ref exactly as it appears in `photos[]`
    ///   (`duo-photos/<duo>/<uuid>.jpg`). Legacy `http` seed entries can't be deleted
    ///   from Storage — we just drop them from the array.
    /// - Returns: the updated `photos[]` array (paths).
    func removePhoto(_ path: String, fromDuo duoId: UUID, existingPhotos: [String]) async throws -> [String] {
        let isStorageObject = !path.hasPrefix("http")
        if isStorageObject {
            do {
                _ = try await supabase.storage
                    .from(Self.bucket)
                    .remove(paths: [objectPath(from: path)])
            } catch {
                // Tolerate "already gone" (404/not found); rethrow anything else so we
                // don't remove the array entry while a real object still exists.
                let desc = "\(error)".lowercased()
                let alreadyGone = desc.contains("not found") || desc.contains("404") || desc.contains("does not exist")
                guard alreadyGone else {
                    throw DuoPhotoError.removeFailed(error.localizedDescription)
                }
                print("ℹ️ Storage object already gone for \(path) — dropping array entry anyway")
            }
        }

        let updated = existingPhotos.filter { $0 != path }
        try await supabase
            .from("duo_profile")
            .update(["photos": updated])
            .eq("id", value: duoId.uuidString)
            .execute()

        return updated
    }

    // MARK: - Helpers

    /// Strip a leading `duo-photos/` so callers can pass either the stored path
    /// (with prefix) or a bucket-relative path to the Storage client.
    private func objectPath(from stored: String) -> String {
        let prefix = "\(Self.bucket)/"
        return stored.hasPrefix(prefix) ? String(stored.dropFirst(prefix.count)) : stored
    }

    /// Resize (if needed) and compress to a ≤ 1 MB JPEG (§6). Steps quality down,
    /// then downscales, until it fits.
    private static func compressedJPEG(_ image: UIImage) throws -> Data {
        let sized = resize(image, maxDimension: maxDimension)

        for quality in stride(from: CGFloat(0.8), through: 0.3, by: -0.1) {
            if let data = sized.jpegData(compressionQuality: quality), data.count <= maxBytes {
                return data
            }
        }

        // Still too big at low quality — halve dimensions once more, then take best effort.
        let smaller = resize(sized, maxDimension: maxDimension / 2)
        guard let data = smaller.jpegData(compressionQuality: 0.5) else {
            throw DuoPhotoError.processingFailed
        }
        guard data.count <= maxBytes else {
            throw DuoPhotoError.tooLarge(Double(data.count) / 1_048_576)
        }
        return data
    }

    /// Aspect-preserving downscale to fit within `maxDimension`. No-op if already smaller.
    private static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxDimension || size.height > maxDimension else { return image }

        let aspect = size.width / size.height
        let newSize = size.width > size.height
            ? CGSize(width: maxDimension, height: maxDimension / aspect)
            : CGSize(width: maxDimension * aspect, height: maxDimension)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Errors

enum DuoPhotoError: LocalizedError {
    case tooMany(Int)
    case tooLarge(Double)
    case processingFailed
    case removeFailed(String)

    var errorDescription: String? {
        switch self {
        case .tooMany(let max):
            return "A duo can have at most \(max) photos."
        case .tooLarge(let mb):
            return "That photo is too large (\(String(format: "%.1f", mb)) MB) even after compression."
        case .processingFailed:
            return "Couldn't process that image. Try a different photo."
        case .removeFailed(let m):
            return "Couldn't remove that photo: \(m)"
        }
    }
}
