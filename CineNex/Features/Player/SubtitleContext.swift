//
//  SubtitleContext.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

struct SubtitleContext: Sendable, Equatable {
    let imdbID: String
    let type: PlaybackMediaKind
    let season: Int?
    let episode: Int?
}
