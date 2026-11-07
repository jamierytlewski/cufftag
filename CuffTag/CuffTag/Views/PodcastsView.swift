import SwiftUI

struct ApplePodcastsView: View {
  @EnvironmentObject private var performer: ActionPerformer

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("One library. Your sleeve.")
            .font(Theme.title(.title2))
            .accessibilityAddTraits(.isHeader)
          Text("Keep your shows and listening history in Apple Podcasts. CuffTag requests playback actions through your Shortcuts; it does not import or duplicate your library.")
            .foregroundStyle(Theme.muted)
          Button("Open Apple Podcasts", systemImage: "mic.fill") {
            Task {
              guard let url = URL(string: "podcasts://"),
                await UIApplication.shared.open(url) else {
                performer.problem = "Couldn't open Apple Podcasts. Check that it is installed."
                return
              }
            }
          }
          .frame(minHeight: 44)
        }
        Section {
          ApplePodcastsShortcutFields()
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Open Shortcuts", systemImage: "square.2.layers.3d.fill") {
            Task {
              guard let url = URL(string: "shortcuts://"),
                await UIApplication.shared.open(url) else {
                performer.problem = "Couldn't open Shortcuts. Check that it is installed."
                return
              }
            }
          }
          .frame(minHeight: 44)
        } header: {
          Text("Your playback Shortcuts")
        } footer: {
          Text("Create and test three Shortcuts in Apple's Shortcuts app: Play / Pause, Seek Forward 30 seconds, and Seek Backward 15 seconds on Now Playing. Enter their exact names above. Available actions and behavior depend on iOS and the playing app.")
        }
        Section {
          Label("Double tap → Play / Pause", systemImage: "hand.tap.fill")
          Label("Brush in → Skip 30s", systemImage: "arrow.left.to.line")
          Label("Brush out → Back 15s", systemImage: "arrow.right.to.line")
          Text("These are the initial Everyday mappings. Your saved profiles still control what each gesture does; change them in Gestures.")
            .font(.footnote).foregroundStyle(Theme.muted)
          Text("When CuffTag is in the background or your phone is locked, tap the notification and unlock if asked. Opening Shortcuts requests an action; it does not confirm that playback changed.")
            .foregroundStyle(Theme.muted)
        } header: {
          Text("From your sleeve")
        }
      }
      .scrollContentBackground(.hidden)
      .background(Theme.background)
      .navigationTitle("Podcasts")
    }
  }
}
