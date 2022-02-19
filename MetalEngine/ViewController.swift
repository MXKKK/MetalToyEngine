//
//  ViewController.swift
//  MetalEngine
//
//  Created by 马西开 on 2021/11/11.
//

import Cocoa
import MetalKit

class ViewController: LocalViewController {

//    var renderer: Renderer?
    var renderer: ssrRenderer?
    override func viewDidLoad() {
        super.viewDidLoad()
        

        // Do any additional setup after loading the view.
        guard let metalView = view as? MTKView else {
          fatalError("metal view not set up in storyboard")
        }
        
        renderer = ssrRenderer(metalView: metalView)
        addGestureRecognizers(to: metalView)
        let scene = TestScene(sceneSize: metalView.bounds.size)
        
        renderer?.setRenderProperties(metalView: metalView, sc: scene)
        renderer?.scene = scene
        
        
        if let gameView = metalView as? GameView {
          gameView.inputController = scene.inputController
        }

    }

    


}

