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
        .task {
            await viewModel.fetchRecentFoods()
        }
        .onChange(of: viewModel.didLogFood) { _, didLog in
            if didLog {
                viewModel.didLogFood = false
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
                .onSubmit {
                    viewModel.handleSearchSubmitted()
                }
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
        if viewModel.isSearching && viewModel.searchResults.isEmpty {
            Spacer()
            ProgressView("Searching...")
            Spacer()
        } else if let error = viewModel.errorMessage {
            Spacer()
            errorView(error)
            Spacer()
        } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty
                    && viewModel.searchQuery.count >= 1 {
            Spacer()
            emptyStateView
            Spacer()
        } else if viewModel.searchResults.isEmpty {
            if !viewModel.recentFoods.isEmpty {
                recentFoodsSection
            } else {
                Spacer()
                promptView
                Spacer()
            }
        } else {
            VStack(spacing: 0) {
                if viewModel.isSearchingFull {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Searching more sources...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                resultsList
            }
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

    // MARK: - Recent Foods

    private var recentFoodsSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recently Logged")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.top, 8)

                LazyVStack(spacing: 1) {
                    ForEach(viewModel.recentFoods) { entry in
                        recentFoodRow(entry)
                    }
                }
            }
        }
    }

    private func recentFoodRow(_ entry: MealEntry) -> some View {
        Button {
            viewModel.searchQuery = entry.foodDescription ?? ""
            viewModel.handleSearchSubmitted()
        } label: {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.foodDescription ?? "Food item")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let serving = entry.servingSizeG {
                            Text("\(serving.noDecimal)g")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Text(entry.mealType.capitalized)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Text("\(entry.calories.noDecimal) kcal")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(.systemBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.foodDescription ?? "Food"), \(entry.calories.noDecimal) calories. Tap to search.")
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "fork.knife")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No results found")
                .font(.headline)
            Text("Try a different search or add a custom food.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            NavigationLink(destination: CustomFoodView(viewModel: viewModel) {
                dismiss()
            }) {
                Text("Add Custom Food")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Add custom food instead")
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
        .accessibilityLabel("\(food.foodName), \(food.brand ?? ""), \(food.caloriesPer100g.noDecimal) calories per 100 grams")
    }
}

#Preview {
    NavigationStack {
        FoodSearchView(viewModel: FoodSearchViewModel())
    }
}
