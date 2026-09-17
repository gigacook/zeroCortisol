import SwiftUI
import ZeroCortisolCore

struct ArchiveView: View {
    @Bindable var model: AppModel
    @State private var expanded = false
    @State private var newTagName = ""

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Picker("Tag", selection: $model.archiveFilter) {
                        Text("All pins").tag(ArchiveFilter.all)
                        Text("Untagged").tag(ArchiveFilter.untagged)
                        if !model.tags.isEmpty {
                            Divider()
                            ForEach(model.tags) { tag in
                                Text(tag.name).tag(ArchiveFilter.tag(tag.id))
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(maxWidth: 160)

                    if case .tag(let id) = model.archiveFilter, let tag = model.tags.first(where: { $0.id == id }) {
                        Button {
                            model.deleteTag(tag)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Delete tag “\(tag.name)” (pins stay)")
                    }
                    Spacer()
                    TextField("New tag", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 100)
                        .onSubmit {
                            model.createTag(named: newTagName)
                            newTagName = ""
                        }
                }

                if model.archivePins.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(model.archivePins) { pin in
                                PinRow(model: model, pin: pin)
                                if pin.id != model.archivePins.last?.id { Divider() }
                            }
                        }
                        .padding(.trailing, 6)
                    }
                    .frame(maxHeight: 230)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Archive")
                .font(.system(size: 12, weight: .semibold))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { expanded.toggle() } }
        }
    }

    private var emptyMessage: String {
        switch model.archiveFilter {
        case .all: return "No pins yet. Pin the Truth of the Day to start your archive."
        case .untagged: return "Every pin has a tag."
        case .tag: return "No pins under this tag."
        }
    }
}

struct PinRow: View {
    @Bindable var model: AppModel
    let pin: Pin
    @State private var addingTag = false
    @State private var tagName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(pin.quote.text)
                .font(.system(size: 12, design: .serif))
                .lineLimit(4)
                .help(pin.quote.text)
            Text("\(pin.quote.author) — \(pin.quote.work)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(pin.tags) { tag in
                    HStack(spacing: 2) {
                        Text(tag.name)
                        Button {
                            model.removeTag(tag, from: pin)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .buttonStyle(.borderless)
                        .help("Remove tag")
                    }
                    .font(.system(size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
                }

                Menu {
                    let available = model.tags.filter { tag in !pin.tags.contains(tag) }
                    ForEach(available) { tag in
                        Button(tag.name) { model.addTag(tag, to: pin) }
                    }
                    if !available.isEmpty { Divider() }
                    Button("New tag…") { addingTag = true }
                } label: {
                    Image(systemName: "tag")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Add tag")

                Spacer()

                Button {
                    model.unpin(pin)
                } label: {
                    Image(systemName: "pin.slash")
                }
                .buttonStyle(.borderless)
                .help("Unpin")
            }

            if addingTag {
                HStack {
                    TextField("Tag name", text: $tagName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(commitTag)
                    Button("Add", action: commitTag).controlSize(.small)
                    Button("Cancel") { addingTag = false; tagName = "" }.controlSize(.small)
                }
            }
        }
    }

    private func commitTag() {
        model.addTag(named: tagName, to: pin)
        tagName = ""
        addingTag = false
    }
}
