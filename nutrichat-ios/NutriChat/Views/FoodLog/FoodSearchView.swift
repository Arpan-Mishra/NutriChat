import SwiftUI
import OSLog

private let logger = Logger(subsystem: "app.nutrichat", category: "FoodSearchView")

/// Food search screen — search bar, results list, navigation to detail.
struct FoodSearchView: View {
    @Bindable var viewModel: FoodSearchViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showBarcodeScanner = false
    @State private var scannedFood: FoodSearchResult?

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showBarcodeScanner = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                }
                .accessibilityLabel("Scan barcode")
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: CustomFoodView(viewModel: viewModel) {
                    dismiss()
                }) {
                    Text("Custom")
                        .font(.subheadline)
                }
                .accessibilityLabel("Add custom food")
            }
        }
        .navigationDestination(isPresented: $showBarcodeScanner) {
            BarcodeScannerView(viewModel: viewModel) { food in
                scannedFood = food
                showBarcodeScanner = false
            }
        }
        .navigationDestination(item: $scannedFood) { food in
            FoodDetailView(food: food, viewModel: viewModel) {
                dismiss()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search foods...", text: $viewModel.searchQuery)
                .textContentType(.none)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.handleSearchQueryChanged()
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                    viewModel.searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching {
            Spacer()
            ProgressView("Searching...")
            Spacer()
        } else if let error = viewModel.errorMessage {
            Spacer()
            errorView(error)
            Spacer()
        } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty
                    && viewModel.searchQuery.count >= 2 {
            Spacer()
            emptyStateView
            Spacer()
        } else if viewModel.searchResults.isEmpty {
            Spacer()
            promptView
            Spacer()
        } else {
            resultsList
        }
    }

    private var promptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Search for a food to log")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No results found")
                .font(.headline)
            Text("Try a different search or add a custom food")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Text(error)
                .font(.subheadline)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            Button("Retry") {
                viewModel.handleSearchQueryChanged()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.searchResults) { food in
                    NavigationLink {
                        FoodDetailView(
                            food: food,
                            viewModel: viewModel
                        ) {
                            dismiss()
                        }
                    } label: {
                        foodRow(food)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func foodRow(_ food: FoodSearchResult) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(food.foodName)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    if let brand = food.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(food.servingDescription)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(food.caloriesPer100g.noDecimal)")
                    .font(.subheadline.weight(.semibold).monospaced())
                Text("kcal/100g")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        FoodSearchView(viewModel: FoodSearchViewModel())
    }
}
