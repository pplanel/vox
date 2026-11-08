//
//  IssueIDTests.swift
//  voxTests
//
//  Created by Pedro Planel on 03/11/26.
//

import Testing
@testable import vox

struct IssueIDTests {
    @Test("Already written as an ID", arguments: [
        "pede pra Liet resolver o HGR-217",
        "pede pra Liet resolver o HGR 217",
        "pede pra Liet resolver o HGR217",
        "pede pra Liet resolver o HGR-217.",
    ])
    func written(_ text: String) {
        #expect(IssueID.find(in: text)?.id == "HGR-217")
    }

    @Test("Spelled letters", arguments: [
        "resolver o agá gê erre 217",
        "resolver o Agá, gê, erre 217",
        "resolver o aga ge erre traço 217",
        "resolver o H G R 217",
    ])
    func spelled(_ text: String) {
        #expect(IssueID.find(in: text)?.id == "HGR-217")
    }

    @Test("Numbers in words", arguments: [
        "resolver o agá gê erre duzentos e dezessete",
        "resolver o HGR duzentos e dezessete",
        "resolver o agá gê erre hífen dois um sete",
        "resolver o HGR duzentos e 17",
    ])
    func numberWords(_ text: String) {
        #expect(IssueID.find(in: text)?.id == "HGR-217")
    }

    @Test func numberParsing() {
        #expect(IssueID.number(from: ["duzentos", "e", "dezessete"]) == "217")
        #expect(IssueID.number(from: ["mil", "e", "vinte"]) == "1020")
        #expect(IssueID.number(from: ["dois", "mil", "e", "dezessete"]) == "2017")
        #expect(IssueID.number(from: ["dois", "um", "sete"]) == "217")
        #expect(IssueID.number(from: ["0", "4", "2"]) == "042")
        #expect(IssueID.number(from: ["vinte", "e", "um"]) == "21")
    }

    /// Words that are also letter names ("de", "o") must not join the prefix.
    @Test func ignoresWordsBeforeThePrefix() {
        #expect(IssueID.find(in: "o bug de agá gê erre duzentos e dezessete")?.id == "HGR-217")
        #expect(IssueID.find(in: "resolver esse HGR 217")?.id == "HGR-217")
    }

    @Test func rangeCoversTheSpokenID() throws {
        let text = "pede pra Liet resolver o agá gê erre duzentos e dezessete e abrir um PR"
        let match = try #require(IssueID.find(in: text))
        #expect(text[match.range] == "agá gê erre duzentos e dezessete")
    }

    @Test("No ID, no guess", arguments: [
        "abre o claude no cognia e pede pra Liet revisar o código",
        "abre o pi no vox e pede pra corrigir os 2 testes",
        "pede pra ele rodar um teste",
        "abre o claude no nix darwin",
        "pede pra rodar o teste dois",
        "",
    ])
    func noID(_ text: String) {
        #expect(IssueID.find(in: text) == nil)
    }
}
