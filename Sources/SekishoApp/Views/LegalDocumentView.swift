import SwiftUI

enum SekishoLegalDocument {
    case terms
    case privacy

    var title: String {
        switch self {
        case .terms:
            "利用規約"
        case .privacy:
            "プライバシー"
        }
    }
}

struct LegalDocumentView: View {
    @Environment(\.dismiss) private var dismiss
    let document: SekishoLegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                WardrobeHeader(title: document.title) {
                    dismiss()
                }

                Text("最終更新日：2026年8月15日")
                    .font(.footnote)
                    .foregroundStyle(Color.sekishoSecondaryInk)

                ForEach(sections.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sections[index].title)
                            .font(.headline)

                        Text(sections[index].body)
                            .font(.body)
                            .foregroundStyle(Color.sekishoSecondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if document == .terms {
                    Link(
                        destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
                    ) {
                        Label("Apple標準使用許諾契約を確認", systemImage: "arrow.up.right.square")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.sekishoVermilion)
                } else {
                    Link(
                        destination: URL(string: "https://www.revenuecat.com/privacy")!
                    ) {
                        Label("RevenueCatのプライバシーポリシー", systemImage: "arrow.up.right.square")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color.sekishoVermilion)
                }

                Link("お問い合わせ：onikun94@gmail.com", destination: URL(string: "mailto:onikun94@gmail.com")!)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.sekishoVermilion)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .foregroundStyle(Color.sekishoInk)
        .background(Color.sekishoPaper.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sections: [(title: String, body: String)] {
        switch document {
        case .terms:
            [
                (
                    "本アプリについて",
                    "関所（Sekisho）は、AppleのScreen Time機能を利用して、利用者が選んだアプリやWebサイトの使用時間を見守るためのアプリです。利用を開始した時点で、本規約とApple標準使用許諾契約に同意したものとします。"
                ),
                (
                    "制限機能",
                    "制限の適用や利用時間の集計はiOSのScreen Time機能に依存します。OSの状態、権限設定、再起動などにより反映が遅れる場合があります。本アプリは重要な安全管理や緊急用途を目的としたものではありません。"
                ),
                (
                    "サブスクリプション",
                    "関所Proは自動更新サブスクリプションです。購入はApple IDに請求され、期間終了の24時間前までに解約しない限り自動更新されます。プランの管理と解約はApp Storeのアカウント設定から行えます。無料体験はApp Storeが適格と判定した場合にのみ適用されます。"
                ),
                (
                    "禁止事項と変更",
                    "法令に違反する目的や、本アプリ・関連サービスの動作を妨害する目的で利用してはいけません。機能や本規約は、法令やサービス内容の変更に応じて更新される場合があります。"
                )
            ]
        case .privacy:
            [
                (
                    "Screen Timeデータ",
                    "選択したアプリ・カテゴリ・Webサイト、利用上限、利用時間の集計結果、制限状態は端末とアプリグループ内に保存されます。これらのScreen Time利用データを開発者のサーバーへ送信したり、販売したりすることはありません。"
                ),
                (
                    "購入情報",
                    "課金処理にはAppleのApp StoreとRevenueCatを利用します。購入状態の確認に必要な取引情報、端末やOSに関する技術情報、匿名のアプリユーザー識別子がRevenueCatで処理される場合があります。Screen Timeの利用時間や選択対象はRevenueCatへ送信しません。"
                ),
                (
                    "通知と保存期間",
                    "関所からの通知は端末上で設定されます。端末内の設定や記録は、アプリを削除することで削除できます。「アプリ削除を防ぐ」がONの場合は、先に設定画面でOFFにしてください。AppleやRevenueCatが処理する購入情報には、それぞれの保存方針が適用されます。"
                ),
                (
                    "お問い合わせ",
                    "本ポリシーやデータの取り扱いに関する質問は、下記メールアドレスへご連絡ください。"
                )
            ]
        }
    }
}

#Preview {
    NavigationStack {
        LegalDocumentView(document: .privacy)
    }
}
