import SwiftUI

/// Inline failure message for a sheet that stays open after a failed action.
///
/// A sheet covers the list underneath it, so the list's `.errorToast` is not visible while the
/// sheet is up — without this, a failed create looks like nothing happened.
struct SheetErrorMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(AppColors.error)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
