import SwiftUI
import UIKit

/// Lets a sheet report an attempted interactive dismissal while retaining the
/// presentation controller's existing delegate behavior.
struct DraftDismissalProtection: UIViewControllerRepresentable {
    @Binding var isDirty: Bool
    @Binding var isDiscardPromptPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isDirty: $isDirty, isDiscardPromptPresented: $isDiscardPromptPresented)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = PresentationProbeViewController()
        controller.view.isHidden = true
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.isDirty = $isDirty
        context.coordinator.isDiscardPromptPresented = $isDiscardPromptPresented
        (controller as? PresentationProbeViewController)?.onPresentationHierarchyChange = { [weak coordinator = context.coordinator] controller in
            coordinator?.install(on: controller)
        }
        context.coordinator.install(on: controller)
    }

    static func dismantleUIViewController(_ controller: UIViewController, coordinator: Coordinator) {
        (controller as? PresentationProbeViewController)?.onPresentationHierarchyChange = nil
        coordinator.restoreDelegate()
        coordinator.active = false
    }

    private final class PresentationProbeViewController: UIViewController {
        var onPresentationHierarchyChange: ((UIViewController) -> Void)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onPresentationHierarchyChange?(self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onPresentationHierarchyChange?(self)
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isDirty: Binding<Bool>
        var isDiscardPromptPresented: Binding<Bool>
        fileprivate var active = true
        private weak var presentationController: UIPresentationController?
        private weak var previousDelegate: (any UIAdaptivePresentationControllerDelegate)?

        init(isDirty: Binding<Bool>, isDiscardPromptPresented: Binding<Bool>) {
            self.isDirty = isDirty
            self.isDiscardPromptPresented = isDiscardPromptPresented
        }

        func install(on controller: UIViewController) {
            guard active else { return }
            var candidate: UIViewController? = controller
            while let current = candidate {
                if let presentation = current.presentationController {
                    if presentationController !== presentation {
                        restoreDelegate()
                        previousDelegate = presentation.delegate
                        presentationController = presentation
                        presentation.delegate = self
                    } else if presentation.delegate !== self {
                        previousDelegate = presentation.delegate
                        presentation.delegate = self
                    }
                    return
                }
                candidate = current.parent
            }
        }

        func restoreDelegate() {
            if let presentationController, presentationController.delegate === self {
                presentationController.delegate = previousDelegate
            }
            presentationController = nil
            previousDelegate = nil
        }

        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool {
            guard isDirty.wrappedValue else {
                return previousDelegate?.presentationControllerShouldDismiss?(presentationController) ?? true
            }
            return false
        }

        func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
            previousDelegate?.presentationControllerDidAttemptToDismiss?(presentationController)
            if isDirty.wrappedValue {
                isDiscardPromptPresented.wrappedValue = true
            }
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector!) -> Any? {
            if let previousDelegate, previousDelegate.responds(to: selector) {
                return previousDelegate
            }
            return super.forwardingTarget(for: selector)
        }
    }
}

extension View {
    func protectDraftDismissal(
        isDirty: Binding<Bool>,
        isDiscardPromptPresented: Binding<Bool>
    ) -> some View {
        background {
            DraftDismissalProtection(
                isDirty: isDirty,
                isDiscardPromptPresented: isDiscardPromptPresented
            )
            .frame(width: 0, height: 0)
        }
    }
}
